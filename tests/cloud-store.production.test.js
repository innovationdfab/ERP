import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Run the actual source against an isolated fake Supabase RPC. This validates
// browser save ordering without credentials, live tables, or an altered UI.
const source = readFileSync(new URL('../src/backend/cloud-store.js', import.meta.url), 'utf8')
  .replace("import { backendConfigured, rpc } from './supabase-rest.js';", 'const backendConfigured = true; const rpc = (...args) => globalThis.__erpProductionTestRpc(...args);');
const cloudModule = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const { initializeCloudStore, writeCloudValue, readCloudValue, flushCloudWrites,
  writeCloudBatchConfirmed, setCloudAccessToken, resetCloudWriteErrors } = cloudModule;

function createRpc(initial = {}) {
  const saved = new Map(Object.entries(initial));
  const calls = [];
  let denyWrites = false;
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
  return { saved, calls, setDenyWrites: value => { denyWrites = value; }, setMissingBatch: value => { missingBatch = value; }, setMissingCas: value => { missingCas = value; } };
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
