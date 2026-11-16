import { backendConfigured, rpc } from './supabase-rest.js';

const cache = new Map();
// Last confirmed database payloads. Optimistic UI changes are never used as
// compare-and-swap expectations for a later write.
const committed = new Map();
let accessToken = '';
let initialized = false;
let writeQueue = Promise.resolve();
let writeErrors = [];

function emit(name, detail) {
  if (typeof window === 'undefined' || typeof window.dispatchEvent !== 'function') return;
  const EventCtor = typeof CustomEvent === 'function' ? CustomEvent : window.CustomEvent;
  if (!EventCtor) return;
  window.dispatchEvent(new EventCtor(name, detail === undefined ? undefined : { detail }));
}

export function setCloudAccessToken(token = '') {
  accessToken = token;
  if (!token) { initialized = false; cache.clear(); committed.clear(); emit('erp-cloud-change', { type: 'logout' }); }
}

export function isCloudStoreReady() {
  return initialized;
}

export async function initializeCloudStore(token) {
  if (!backendConfigured) {
    throw new Error('Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to .env.');
  }
  if (initialized) await flushCloudWrites();
  accessToken = token || '';
  const rows = await rpc('erp_get_ui_state', {}, { accessToken });
  cache.clear();
  committed.clear();
  for (const row of rows || []) { cache.set(row.storage_key, row.payload); committed.set(row.storage_key, row.payload); }
  writeErrors = [];
  initialized = true;
  emit('erp-cloud-ready');
  emit('erp-cloud-change', { type: 'hydrate' });
  return cache.size;
}

export function readCloudValue(key, fallback) {
  return cache.has(key) ? cache.get(key) : fallback;
}

function assertCloudKey(key) {
  if (typeof key !== 'string' || !key.trim() || (initialized && !/^dfab-[a-zA-Z0-9 /_.-]+$/.test(key))) {
    throw new Error('Unsupported ERP storage section.');
  }
}

function assertWriteAllowed() {
  if (writeErrors.length) throw new Error('ERP database has unsaved changes. Reload after resolving the save error; no more writes will be queued.');
}

function reportWriteFailure(key, error) {
  writeErrors.push({ key, error });
  // Do not continue displaying optimistic collection data as if it was saved.
  // The last confirmed snapshot remains authoritative until reconciliation.
  cache.clear();
  for (const [savedKey, value] of committed.entries()) cache.set(savedKey, value);
  emit('erp-cloud-change', { type: 'rollback-unconfirmed' });
  emit('erp-storage-error', `Database save failed for ${key}: ${error.message}`);
}

function scheduleWrite(key, action) {
  const token = accessToken;
  writeQueue = writeQueue.catch(() => undefined).then(async () => {
    assertWriteAllowed();
    if (!initialized || accessToken !== token) throw new Error('ERP session changed before the pending save was completed.');
    await action(token);
  }).catch(error => {
    // Preserve the first failure for flushCloudWrites and block subsequent writes.
    if (!writeErrors.length) reportWriteFailure(key, error);
    throw error;
  });
}

// Existing synchronous caller contract is preserved for forms that use optimistic
// state. Only confirmed writes update `committed`; a failure blocks further saves.
export function writeCloudValue(key, value) {
  assertCloudKey(key);
  assertWriteAllowed();
  cache.set(key, value);
  emit('erp-cloud-change', { type: 'write', key });
  if (!initialized || !accessToken) return true;
  scheduleWrite(key, async token => {
    const expected = committed.has(key) ? committed.get(key) : null;
    try {
      await rpc('erp_put_ui_state_if_unchanged', { p_storage_key: key, p_expected: expected, p_payload: value }, { accessToken: token });
    } catch (error) {
      if (!isMissingIntegrityRpc(error, 'erp_put_ui_state_if_unchanged')) throw error;
      throw new Error('Secure Supabase saving is not installed. Apply ERP_FLOW_INTEGRITY_UPGRADE.sql in staging first; no overwrite was attempted.');
    }
    committed.set(key, value);
    emit('erp-storage-saved', { key });
  });
  return true;
}

export function removeCloudValue(key) {
  assertCloudKey(key);
  assertWriteAllowed();
  cache.delete(key);
  emit('erp-cloud-change', { type: 'delete', key });
  if (!initialized || !accessToken) return false;
  scheduleWrite(key, async token => {
    const expected = committed.has(key) ? committed.get(key) : null;
    try {
      await rpc('erp_delete_ui_state_if_unchanged', { p_storage_key: key, p_expected: expected }, { accessToken: token });
    } catch (error) {
      if (!isMissingIntegrityRpc(error, 'erp_delete_ui_state_if_unchanged')) throw error;
      throw new Error('Secure Supabase deletion is not installed. Apply ERP_PRODUCTION_GUARDRAILS.sql in staging first.');
    }
    committed.delete(key);
    emit('erp-storage-saved', { key });
  });
  return true;
}

export function resetCloudWriteErrors() {
  if (initialized && writeErrors.length) throw new Error('A previous ERP save failed. Reload and reconcile the database before continuing.');
  writeErrors = [];
}

export async function flushCloudWrites() {
  try { await writeQueue; } catch {}
  if (writeErrors.length) {
    const first = writeErrors[0];
    const error = Object.assign(
      new Error(`${writeErrors.length} database write(s) failed. First failure: ${first.key} — ${first.error?.message || first.error}`),
      {failures:[...writeErrors]}
    );
    throw error;
  }
}

export function exportCloudSnapshot() {
  return Object.fromEntries(cache.entries());
}

function isMissingIntegrityRpc(error, name) {
  const message=String(error?.message || '');
  return /function|schema cache|not found|PGRST202/i.test(message) && message.includes(name);
}

/** Confirmed write with concurrency protection when the additive SQL upgrade is installed. */
export async function writeCloudValueConfirmed(key, value, visibleValue) {
  if (!initialized || !accessToken) throw new Error('Supabase session is not ready. Please log in again.');
  if (!key || typeof key !== 'string') throw new Error('A valid ERP storage key is required.');
  const token=accessToken;
  assertCloudKey(key);
  assertWriteAllowed();
  if (visibleValue !== undefined && cache.has(key) && JSON.stringify(visibleValue)!==JSON.stringify(cache.get(key))) throw new Error('The ERP data changed since this page was opened. Reopen the page before saving.');
  const operation=writeQueue.catch(() => undefined).then(async () => {
    assertWriteAllowed();
    const expected=committed.has(key)?committed.get(key):null;
    if (accessToken !== token || !initialized) throw new Error('ERP session changed during save.');
    try {
      await rpc('erp_put_ui_state_if_unchanged', {p_storage_key:key,p_expected:expected,p_payload:value}, {accessToken:token});
    } catch (error) {
      if (!isMissingIntegrityRpc(error,'erp_put_ui_state_if_unchanged')) throw error;
      throw new Error('Secure Supabase saving is not installed. Apply ERP_FLOW_INTEGRITY_UPGRADE.sql in staging first.');
    }
    cache.set(key,value);
    committed.set(key,value);
    emit('erp-cloud-change',{type:'confirmed-write',key});
    emit('erp-storage-saved',{key});
  });
  writeQueue=operation;
  try { await operation; }
  catch(error) {
    writeErrors.push({key,error});
    emit('erp-storage-error', `Database save failed for ${key}: ${error.message}`);
    throw error;
  }
}

/** Connected handoffs commit downstream record, link, and invoice detail atomically.
 * Missing SQL upgrade is a hard error: never partially write a transaction. */
export async function writeCloudBatchConfirmed(changes) {
  if (!initialized || !accessToken) throw new Error('Supabase session is not ready. Please log in again.');
  if (!Array.isArray(changes) || changes.length < 2 || changes.length > 3) throw new Error('Two or three ERP sections required.');
  assertWriteAllowed();
  for (const {key} of changes) assertCloudKey(key);
  if (new Set(changes.map(item => item.key)).size !== changes.length) throw new Error('Duplicate ERP storage keys in one batch.');
  const token=accessToken;
  for(const {key,expected} of changes){
    if(expected!==undefined && cache.has(key) && JSON.stringify(expected)!==JSON.stringify(cache.get(key))) throw new Error(`The ${key} records changed since this page was opened. Reload before saving.`);
  }
  const operation=writeQueue.catch(() => undefined).then(async () => {
    assertWriteAllowed();
    const expectedChanges=changes.map(({key,value})=>({key,expected:committed.has(key)?committed.get(key):null,payload:value}));
    if (accessToken !== token || !initialized) throw new Error('ERP session changed during save.');
    try {
      await rpc('erp_commit_ui_state_batch',{p_changes:expectedChanges},{accessToken:token});
    } catch(error) {
      if (!isMissingIntegrityRpc(error,'erp_commit_ui_state_batch')) throw error;
      // A partial multi-document save would corrupt transaction lineage. Fail
      // closed until the atomic SQL upgrade is installed in Supabase.
      throw new Error('Atomic workflow saving is unavailable. Apply supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql and retry; no document was created.');
    }
    for(const item of expectedChanges) {
      cache.set(item.key,item.payload);
      committed.set(item.key,item.payload);
      emit('erp-cloud-change',{type:'confirmed-write',key:item.key});
      emit('erp-storage-saved',{key:item.key});
    }
  });
  writeQueue=operation;
  try {await operation;}
  catch(error) {
    writeErrors.push({key:'workflow-batch',error});
    emit('erp-storage-error',`Connected document save failed: ${error.message}`);
    throw error;
  }
}
