import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Run the actual source against an isolated fake Supabase RPC. This validates
// browser save ordering without credentials, live tables, or an altered UI.
const source = readFileSync(new URL('../src/backend/cloud-store.js', import.meta.url), 'utf8')
  .replace("import {confirmedOperation} from '../operation-feedback.js';",`import {confirmedOperation} from '${new URL('../src/operation-feedback.js',import.meta.url).href}';`)
  .replace("import { backendConfigured, rpc } from './supabase-rest.js';", 'const backendConfigured = true; const rpc = (...args) => globalThis.__erpProductionTestRpc(...args);');
const cloudModule = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const { initializeCloudStore, writeCloudValue, readCloudValue, flushCloudWrites,
  writeCloudBatchConfirmed, commitProcessChanges, nextProcessNumber, setCloudAccessToken, resetCloudWriteErrors } = cloudModule;

function createRpc(initial = {}) {
  const saved = new Map(Object.entries(initial));
  const calls = [];
  let denyWrites = false;let rejectConfirmed=false;let rejectStatus=400;
  let missingBatch = false;
  let missingCas = false;
  globalThis.__erpProductionTestRpc = async (name, params = {}) => {
    calls.push({ name, params });
    if (name === 'erp_get_ui_state') return [...saved].map(([storage_key, payload]) => ({ storage_key, payload }));
    if (name === 'erp_put_ui_state_if_unchanged') {
      if (missingCas) throw Error('function erp_put_ui_state_if_unchanged not found');
      if (denyWrites || JSON.stringify(saved.get(params.p_storage_key) ?? null) !== JSON.stringify(params.p_expected)) throw Error('ERP record changed in another session');
      saved.set(params.p_storage_key, params.p_payload);
      return null;
    }
    if (name === 'erp_next_process_no') return 'SO/LOCAL/26-27/00001';
    if (name === 'erp_commit_process') {
      if(rejectConfirmed){rejectConfirmed=false;throw Object.assign(Error('Party required'),{status:rejectStatus,code:'P0001'});}
      for (const key of Object.keys(params.p_changes)) {
        if (denyWrites || JSON.stringify(saved.get(key) ?? null) !== JSON.stringify(params.p_expected[key])) throw Error('ERP records changed');
      }
      for (const [key,value] of Object.entries(params.p_changes)) saved.set(key,value);
      return null;
    }
    if (name === 'erp_commit_ui_state_batch') {
      if (missingBatch) throw Error('function erp_commit_ui_state_batch not found');
      for (const change of params.p_changes) {
        if (JSON.stringify(saved.get(change.key) ?? null) !== JSON.stringify(change.expected)) throw Error('ERP records changed');
      }
      for (const change of params.p_changes) saved.set(change.key, change.payload);
      return null;
    }
    throw Error(`Unexpected mock RPC ${name}`);
  };
  return { saved, calls, rejectOnce:(status=400)=>{rejectConfirmed=true;rejectStatus=status;}, setDenyWrites: value => { denyWrites = value; }, setMissingBatch: value => { missingBatch = value; }, setMissingCas: value => { missingCas = value; } };
}

test('queued saves use the last committed database payload and do not lose rapid edits', async () => {
  const mock = createRpc({ 'dfab-erp-test': [0] });
  await initializeCloudStore('test-jwt');
  writeCloudValue('dfab-erp-test', [1]);
  writeCloudValue('dfab-erp-test', [2]);
  assert.deepEqual(readCloudValue('dfab-erp-test'), [2]);
  await flushCloudWrites();
  assert.deepEqual(mock.saved.get('dfab-erp-test'), [2]);
  const writes = mock.calls.filter(call => call.name === 'erp_put_ui_state_if_unchanged');
  assert.deepEqual(writes.map(call => call.params.p_expected), [[0], [1]]);
  setCloudAccessToken('');
});

test('database conflict blocks further optimistic saves and surfaces an error', async () => {
  const mock = createRpc({ 'dfab-erp-test': ['initial'] });
  await initializeCloudStore('test-jwt');
  mock.setDenyWrites(true);
  writeCloudValue('dfab-erp-test', ['conflicting']);
  await assert.rejects(flushCloudWrites(), /database write\(s\) failed/i);
  assert.throws(() => writeCloudValue('dfab-erp-test', ['another']), /unsaved changes/i);
  assert.throws(() => resetCloudWriteErrors(), /Reload/);
  assert.deepEqual(mock.saved.get('dfab-erp-test'), ['initial']);
  assert.deepEqual(readCloudValue('dfab-erp-test'), ['initial']); // failed optimistic state is rolled back
  setCloudAccessToken('');
});

test('a missing atomic RPC never performs partial connected-document writes', async () => {
  const mock = createRpc({ 'dfab-erp-Test A': [], 'dfab-workflow-links-v1': [] });
  mock.setMissingBatch(true);
  await initializeCloudStore('test-jwt');
  await assert.rejects(writeCloudBatchConfirmed([
    { key:'dfab-erp-Test A', value:[['A1']], expected:[] },
    { key:'dfab-workflow-links-v1', value:[{created:'A1'}], expected:[] }
  ]), /Atomic workflow saving is unavailable/);
  assert.deepEqual(mock.saved.get('dfab-erp-Test A'), []);
  assert.deepEqual(mock.saved.get('dfab-workflow-links-v1'), []);
  assert.equal(mock.calls.filter(c => c.name === 'erp_put_ui_state').length, 0);
  setCloudAccessToken('');
});

test('missing concurrency RPC fails closed without a legacy overwrite', async () => {
  const mock = createRpc({ 'dfab-erp-test': [7] });
  mock.setMissingCas(true);
  await initializeCloudStore('test-jwt');
  writeCloudValue('dfab-erp-test', [8]);
  await assert.rejects(flushCloudWrites(), /secure Supabase saving is not installed/i);
  assert.deepEqual(mock.saved.get('dfab-erp-test'), [7]);
  assert.equal(mock.calls.filter(call => call.name === 'erp_put_ui_state').length, 0);
  setCloudAccessToken('');
});


test('process commit confirms all sections and supplies the next save with committed state', async () => {
  const mock=createRpc({'dfab-process-a':[0]});
  await initializeCloudStore('process-token');
  await commitProcessChanges({'dfab-process-a':[1],'dfab-process-b':{source:'SO1'}},{'dfab-process-a':[0],'dfab-process-b':null},'handoff');
  assert.deepEqual(mock.saved.get('dfab-process-b'),{source:'SO1'});
  assert.deepEqual(readCloudValue('dfab-process-a'),[1]);
  writeCloudValue('dfab-process-a',[2]);
  await flushCloudWrites();
  assert.deepEqual(mock.saved.get('dfab-process-a'),[2]);
  assert.deepEqual(mock.calls.find(call=>call.name==='erp_commit_process').params.p_action,'handoff');
  setCloudAccessToken('');
});

test('stale process snapshots reject before writing and do not block a fresh edit', async () => {
  const mock=createRpc({'dfab-process-a':[1]});
  await initializeCloudStore('process-token');
  await assert.rejects(commitProcessChanges({'dfab-process-a':[3]},{'dfab-process-a':[0]}),/changed/);
  assert.equal(mock.calls.filter(call=>call.name==='erp_commit_process').length,0);
  await commitProcessChanges({'dfab-process-a':[2]},{'dfab-process-a':[1]});
  assert.deepEqual(mock.saved.get('dfab-process-a'),[2]);
  setCloudAccessToken('');
});

test('process commits wait for queued edits and reject invalid section snapshots', async () => {
  const mock=createRpc({'dfab-process-a':[0]});
  await initializeCloudStore('process-token');
  writeCloudValue('dfab-process-a',[1]);
  await commitProcessChanges({'dfab-process-a':[2]},{'dfab-process-a':[1]});
  assert.deepEqual(mock.saved.get('dfab-process-a'),[2]);
  await assert.rejects(commitProcessChanges({'dfab-process-a':[3]},{}),/snapshot/);
  await assert.rejects(commitProcessChanges({'dfab-process-a':[3]},{'dfab-process-a':[2]},'unknown'),/action/);
  setCloudAccessToken('');
});

test('failed atomic process write preserves every confirmed section and blocks further saves', async () => {
  const mock=createRpc({'dfab-process-a':[0],'dfab-process-b':[0]});
  await initializeCloudStore('process-token');
  mock.setDenyWrites(true);
  await assert.rejects(commitProcessChanges({'dfab-process-a':[1],'dfab-process-b':[1]},{'dfab-process-a':[0],'dfab-process-b':[0]}),/changed/);
  assert.deepEqual(readCloudValue('dfab-process-a'),[0]);
  assert.deepEqual(mock.saved.get('dfab-process-b'),[0]);
  await assert.rejects(flushCloudWrites(),/database write/);
  setCloudAccessToken('');
});

test('an in-flight process commit cannot hydrate a logged-out session', async () => {
  createRpc();
  await initializeCloudStore('process-token');
  let entered,release;
  const started=new Promise(resolve=>{entered=resolve;});
  globalThis.__erpProductionTestRpc=async()=>{entered();await new Promise(resolve=>{release=resolve;});};
  const operation=commitProcessChanges({'dfab-process-a':[1]},{'dfab-process-a':null});
  await started;
  setCloudAccessToken('');release();
  await assert.rejects(operation,/session changed/);
  assert.equal(readCloudValue('dfab-process-a'),undefined);
});

test('process numbers require an active session and use the authenticated numbering RPC', async () => {
  await assert.rejects(nextProcessNumber('Sales Orders','SO/LOCAL','26-27'),/session/);
  const mock=createRpc();
  await initializeCloudStore('number-token');
  assert.equal(await nextProcessNumber('Sales Orders','SO/LOCAL','26-27'),'SO/LOCAL/26-27/00001');
  assert.deepEqual(mock.calls.at(-1).params,{p_document_type:'Sales Orders',p_prefix:'SO/LOCAL',p_financial_year:'26-27'});
  globalThis.__erpProductionTestRpc=async()=>'';
  await assert.rejects(nextProcessNumber('Sales Orders','SO/LOCAL','26-27'),/valid document number/);
  setCloudAccessToken('');
});

 test('confirmed validation rejection leaves later atomic saves available without reload',async()=>{const mock=createRpc({'dfab-erp-Test':[]});await initializeCloudStore('test-jwt');mock.rejectOnce();await assert.rejects(commitProcessChanges({'dfab-erp-Test':[['bad']]},{'dfab-erp-Test':[]}),/Party required/);assert.deepEqual(readCloudValue('dfab-erp-Test'),[]);await commitProcessChanges({'dfab-erp-Test':[['valid']]},{'dfab-erp-Test':[]});assert.deepEqual(mock.saved.get('dfab-erp-Test'),[['valid']]);setCloudAccessToken('');});

 test('request timeout keeps uncertain atomic writes locked until reload',async()=>{const mock=createRpc({'dfab-erp-Test':[]});await initializeCloudStore('test-jwt');mock.rejectOnce(408);await assert.rejects(commitProcessChanges({'dfab-erp-Test':[['uncertain']]},{'dfab-erp-Test':[]}),/Party required/);await assert.rejects(commitProcessChanges({'dfab-erp-Test':[['retry']]},{'dfab-erp-Test':[]}),/failed|unsaved/i);assert.deepEqual(mock.saved.get('dfab-erp-Test'),[]);setCloudAccessToken('');});
