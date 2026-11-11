import test from 'node:test';
import assert from 'node:assert/strict';
import { isoDate, parseCsv, validateBackup } from '../src/erp-utils.js';
import { getRestoredDataStatus, restorePreviousErpDataOnce } from '../src/restored-seed-data.js';
import { readCloudValue, writeCloudValue, setCloudAccessToken } from '../src/backend/cloud-store.js';

test('invalid calendar dates cannot enter ERP transactions', () => {
  assert.equal(isoDate('2026-02-30'), '');
  assert.equal(isoDate('31-Apr-2026'), '');
  assert.equal(isoDate('29-Feb-2024'), '2024-02-29');
  assert.equal(isoDate('2026-10-27'), '2026-10-27');
});

test('historical import does not recreate intentionally deleted records after successful migration', async () => {
  setCloudAccessToken('');
  writeCloudValue('dfab-restored-preclean-data-v3-verified',true);
  writeCloudValue('dfab-erp-products-v3',[]);
  assert.equal(getRestoredDataStatus().complete,true);
  const result=await restorePreviousErpDataOnce();
  assert.equal(result.restored,false);
  assert.deepEqual(readCloudValue('dfab-erp-products-v3',null),[]);
});

test('product import CSV parser retains embedded commas and quoted newlines', () => {
  assert.deepEqual(parseCsv('Code,Description\nP1,"SS, 304"\nP2,"line 1\nline 2"'), [['Code','Description'],['P1','SS, 304'],['P2','line 1\nline 2']]);
});

test('backup validation rejects secrets and tokens', () => {
  assert.throws(()=>validateBackup({records:{'dfab-api-token':'sensitive'}}));
  assert.throws(()=>validateBackup({records:{'dfab-secret-config':{}}}));
});
