import { backendConfigured, rpc } from './supabase-rest.js';

const cache = new Map();
// Last confirmed database payloads. Optimistic UI changes are never used as
// compare-and-swap expectations for a later write.
const committed = new Map();
let accessToken = '';
let sessionRevision = 0;
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
  if (accessToken === token) return;
  accessToken = token;
  sessionRevision++;
  initialized = false;
  cache.clear();
  committed.clear();
  writeQueue = Promise.resolve();
  writeErrors = [];
  emit('erp-cloud-change', { type: token ? 'session' : 'logout' });
}

function assertSession(revision) {
  if (sessionRevision !== revision) throw new Error('ERP session changed before the operation completed.');
}

class QueuedChangeConflict extends Error {}
const samePayload=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const cachedPayload=key=>cache.has(key)?cache.get(key):null;
const committedPayload=key=>committed.has(key)?committed.get(key):null;
function checkQueuedSnapshot(key,expected) {
  if(!samePayload(expected,committedPayload(key))) {
    throw new QueuedChangeConflict(`The ${key} records changed while this save was waiting. Reopen the page and retry.`);
  }
}

export function isCloudStoreReady() {
  return initialized;
}

export async function initializeCloudStore(token) {
  if (!backendConfigured) {
    throw new Error('Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to .env.');
  }
  setCloudAccessToken(token || '');
  const revision=sessionRevision;
  if (initialized) await flushCloudWrites();
  assertSession(revision);
  const rows = await rpc('erp_get_ui_state', {}, { accessToken });
  assertSession(revision);
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
  const token = accessToken, revision = sessionRevision;
  writeQueue = writeQueue.catch(() => undefined).then(async () => {
    assertWriteAllowed();
    if (!initialized || accessToken !== token) throw new Error('ERP session changed before the pending save was completed.');
    assertSession(revision);
    await action(token,revision);
  }).catch(error => {
    // Preserve the first failure for flushCloudWrites and block subsequent writes.
    if (revision===sessionRevision&&!writeErrors.length) reportWriteFailure(key, error);
    throw error;
  });
  void writeQueue.catch(()=>{});
}

// Existing synchronous caller contract is preserved for forms that use optimistic
// state. Only confirmed writes update `committed`; a failure blocks further saves.
export function writeCloudValue(key, value) {
  assertCloudKey(key);
  assertWriteAllowed();
  const base=cachedPayload(key);
  cache.set(key, value);
  emit('erp-cloud-change', { type: 'write', key });
  if (!initialized || !accessToken) return true;
  scheduleWrite(key, async (token,revision) => {
    checkQueuedSnapshot(key,base);
    try {
      await rpc('erp_put_ui_state_if_unchanged', { p_storage_key: key, p_expected: base, p_payload: value }, { accessToken: token });
    } catch (error) {
      if (!isMissingIntegrityRpc(error, 'erp_put_ui_state_if_unchanged')) throw error;
      throw new Error('Secure Supabase saving is not installed. Apply ERP_FLOW_INTEGRITY_UPGRADE.sql in staging first; no overwrite was attempted.');
    }
    assertSession(revision);
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
  scheduleWrite(key, async (token,revision) => {
    const expected = committed.has(key) ? committed.get(key) : null;
    try {
      await rpc('erp_delete_ui_state_if_unchanged', { p_storage_key: key, p_expected: expected }, { accessToken: token });
    } catch (error) {
      if (!isMissingIntegrityRpc(error, 'erp_delete_ui_state_if_unchanged')) throw error;
      throw new Error('Secure Supabase deletion is not installed. Apply ERP_PRODUCTION_GUARDRAILS.sql in staging first.');
    }
    assertSession(revision);
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
  const token=accessToken, revision=sessionRevision;
  assertCloudKey(key);
  assertWriteAllowed();
  const expected=cachedPayload(key);
  if(visibleValue!==undefined&&cache.has(key)&&!samePayload(visibleValue,expected)) {
    throw new QueuedChangeConflict('The ERP data changed since this page was opened. Reopen the page before saving.');
  }
  const operation=writeQueue.catch(() => undefined).then(async () => {
    assertSession(revision);
    assertWriteAllowed();
    checkQueuedSnapshot(key,expected);
    try {
      await rpc('erp_put_ui_state_if_unchanged', {p_storage_key:key,p_expected:expected,p_payload:value}, {accessToken:token});
    } catch (error) {
      if (!isMissingIntegrityRpc(error,'erp_put_ui_state_if_unchanged')) throw error;
      throw new Error('Secure Supabase saving is not installed. Apply ERP_FLOW_INTEGRITY_UPGRADE.sql in staging first.');
    }
    assertSession(revision);
    cache.set(key,value);
    committed.set(key,value);
    emit('erp-cloud-change',{type:'confirmed-write',key});
    emit('erp-storage-saved',{key});
  });
  writeQueue=operation;
  try { await operation; }
  catch(error) {
    if(revision===sessionRevision&&!(error instanceof QueuedChangeConflict)&&!writeErrors.length)reportWriteFailure(key,error);
    throw error;
  }
}

/** Connected handoffs commit downstream record, link, and invoice detail atomically.
 * Missing SQL upgrade is a hard error: never partially write a transaction. */
export async function writeCloudBatchConfirmed(changes) {
  if(!Array.isArray(changes)||changes.length<2||changes.length>3)throw new Error('Two or three ERP sections required.');
  return commitSections(changes,'erp_commit_ui_state_batch');
}
export async function restoreCloudSectionsConfirmed(entries) {
  if(!Array.isArray(entries)||!entries.length||entries.length>500)throw new Error('Choose a backup with 1 to 500 data sections.');
  return commitSections(entries.map(([key,value])=>({key,value})),'erp_restore_ui_state');
}
async function commitSections(changes,rpcName) {
  if (!initialized || !accessToken) throw new Error('Supabase session is not ready. Please log in again.');
  assertWriteAllowed();
  for (const {key} of changes) assertCloudKey(key);
  if (new Set(changes.map(item => item.key)).size !== changes.length) throw new Error('Duplicate ERP storage keys in one batch.');
  const token=accessToken, revision=sessionRevision;
  const expectedChanges=changes.map(({key,expected,value})=>{
    const current=cachedPayload(key);
    if(expected!==undefined&&cache.has(key)&&!samePayload(expected,current)) {
      throw new QueuedChangeConflict(`The ${key} records changed since this page was opened. Reload before saving.`);
    }
    return {key,expected:current,payload:value};
  });
  const operation=writeQueue.catch(() => undefined).then(async () => {
    assertSession(revision);
    assertWriteAllowed();
    for(const {key,expected} of expectedChanges)checkQueuedSnapshot(key,expected);
    try {
      await rpc(rpcName,{p_changes:expectedChanges},{accessToken:token});
    } catch(error) {
      if (!isMissingIntegrityRpc(error,rpcName)) throw error;
      if(rpcName==='erp_restore_ui_state')throw new Error('Atomic restore is unavailable. Apply ERP_WORKSPACE_INTEGRITY.sql first.');
      // A partial multi-document save would corrupt transaction lineage. Fail
      // closed until the atomic SQL upgrade is installed in Supabase.
      throw new Error('Atomic workflow saving is unavailable. Apply supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql and retry; no document was created.');
    }
    assertSession(revision);
    for(const item of expectedChanges) {
      cache.set(item.key,item.payload);
      committed.set(item.key,item.payload);
    }
    for(const item of expectedChanges) {
      emit('erp-cloud-change',{type:'confirmed-write',key:item.key});
      emit('erp-storage-saved',{key:item.key});
    }
  });
  writeQueue=operation;
  try {await operation;}
  catch(error) {
    if(revision===sessionRevision&&!(error instanceof QueuedChangeConflict)&&!writeErrors.length)reportWriteFailure(rpcName,error);
    throw error;
  }
}

/** Save process headers, lines and lineage together, using the edit snapshot. */
export async function commitProcessChanges(changes, expected, action = 'save') {
  if (!initialized || !accessToken) throw new Error('Supabase session is not ready. Please log in again.');
  assertWriteAllowed();
  if (!changes || Array.isArray(changes) || typeof changes !== 'object' ||
      !expected || Array.isArray(expected) || typeof expected !== 'object') throw new Error('Invalid process snapshot.');
  const keys = Object.keys(changes);
  if (!keys.length || keys.length > 500 || keys.length !== Object.keys(expected).length ||
      keys.some(key => !Object.hasOwn(expected, key))) throw new Error('Every process section requires its original snapshot.');
  if (!['save','approve','reject','handoff','payment','close','delete'].includes(action)) throw new Error('Invalid process action.');
  // Detach caller objects before waiting behind any earlier saves.
  const payload = structuredClone(changes), base = structuredClone(expected);
  for (const key of keys) {
    assertCloudKey(key);
    if (!samePayload(base[key], cachedPayload(key))) throw new QueuedChangeConflict('The ERP data changed since this page was opened. Reopen the page before saving.');
  }
  const token = accessToken, revision = sessionRevision;
  const operation = writeQueue.catch(() => undefined).then(async () => {
    assertSession(revision);
    assertWriteAllowed();
    for (const key of keys) checkQueuedSnapshot(key, base[key]);
    try {
      await rpc('erp_commit_process', {p_changes:payload,p_expected:base,p_action:action}, {accessToken:token});
    } catch (error) {
      if (!isMissingIntegrityRpc(error,'erp_commit_process')) throw error;
      throw new Error('Atomic process saving is unavailable. Apply supabase/DFAB_PROCESS_UPGRADE.sql before saving.');
    }
    assertSession(revision);
    for (const key of keys) { cache.set(key,payload[key]); committed.set(key,payload[key]); }
    emit('erp-cloud-change',{type:'process-commit'});
    emit('erp-storage-saved',{key:keys.join(', ')});
  });
  writeQueue = operation;
  try { await operation; }
  catch (error) {
    if (revision === sessionRevision && !(error instanceof QueuedChangeConflict) && !writeErrors.length) reportWriteFailure('erp_commit_process',error);
    throw error;
  }
}

export async function nextProcessNumber(type, prefix, year) {
  if (!initialized || !accessToken) throw new Error('Supabase session is not ready. Please log in again.');
  assertWriteAllowed();
  if ([type,prefix,year].some(value => typeof value !== 'string' || !value.trim())) throw new Error('Document type, prefix and financial year are required.');
  const token = accessToken, revision = sessionRevision;
  await flushCloudWrites();
  assertSession(revision);
  let number;
  try {
    number = await rpc('erp_next_process_no', {p_document_type:type,p_prefix:prefix,p_financial_year:year}, {accessToken:token});
  } catch (error) {
    if (!isMissingIntegrityRpc(error,'erp_next_process_no')) throw error;
    throw new Error('Process numbering is unavailable. Apply supabase/DFAB_PROCESS_UPGRADE.sql first.');
  }
  assertSession(revision);
  if (typeof number !== 'string' || !number.trim()) throw new Error('Supabase did not return a valid document number.');
  return number;
}
