import { backendConfigured, rpc } from './supabase-rest.js';

const cache = new Map();
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
  if (!token) { initialized = false; cache.clear(); emit('erp-cloud-change', { type: 'logout' }); }
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
  for (const row of rows || []) cache.set(row.storage_key, row.payload);
  initialized = true;
  emit('erp-cloud-ready');
  emit('erp-cloud-change', { type: 'hydrate' });
  return cache.size;
}

export function readCloudValue(key, fallback) {
  return cache.has(key) ? cache.get(key) : fallback;
}

export function writeCloudValue(key, value) {
  cache.set(key, value);
  emit('erp-cloud-change', { type: 'write', key });
  if (!initialized || !accessToken) return true;
  writeQueue = writeQueue
    .catch(() => undefined)
    .then(() => rpc('erp_put_ui_state', { p_storage_key: key, p_payload: value }, { accessToken }))
    .then(() => emit('erp-storage-saved', { key }))
    .catch((error) => {
      writeErrors.push({ key, error });
      emit('erp-storage-error', `Database save failed for ${key}: ${error.message}`);
      throw error;
    });
  return true;
}

export function removeCloudValue(key) {
  cache.delete(key);
  emit('erp-cloud-change', { type: 'delete', key });
  if (!initialized || !accessToken) return false;
  writeQueue = writeQueue
    .catch(() => undefined)
    .then(() => rpc('erp_delete_ui_state', { p_storage_key: key }, { accessToken }))
    .catch((error) => {
      writeErrors.push({ key, error });
      emit('erp-storage-error', `Database delete failed for ${key}: ${error.message}`);
      throw error;
    });
  return true;
}

export function resetCloudWriteErrors() {
  writeErrors = [];
}

export async function flushCloudWrites() {
  try { await writeQueue; } catch {}
  if (writeErrors.length) {
    const first = writeErrors[0];
    const error = new Error(`${writeErrors.length} database write(s) failed. First failure: ${first.key} — ${first.error?.message || first.error}`);
    error.failures = [...writeErrors];
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
  const expected=cache.has(key)?cache.get(key):null;
  if (visibleValue !== undefined && cache.has(key) && JSON.stringify(visibleValue)!==JSON.stringify(expected)) throw new Error('The ERP data changed since this page was opened. Reopen the page before saving.');
  const operation=writeQueue.catch(() => undefined).then(async () => {
    if (accessToken !== token || !initialized) throw new Error('ERP session changed during save.');
    try {
      await rpc('erp_put_ui_state_if_unchanged', {p_storage_key:key,p_expected:expected,p_payload:value}, {accessToken:token});
    } catch (error) {
      if (!isMissingIntegrityRpc(error,'erp_put_ui_state_if_unchanged')) throw error;
      await rpc('erp_put_ui_state', {p_storage_key:key,p_payload:value}, {accessToken:token});
    }
    cache.set(key,value);
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

/** Connected handoffs commit downstream record, link, and invoice detail atomically
 * when the optional SQL upgrade is installed. Old deployments retain confirmed,
 * sequential writes; they are NOT atomic until the SQL is applied. */
export async function writeCloudBatchConfirmed(changes) {
  if (!initialized || !accessToken) throw new Error('Supabase session is not ready. Please log in again.');
  if (!Array.isArray(changes) || changes.length < 2 || changes.length > 3) throw new Error('Two or three ERP sections required.');
  const token=accessToken;
  for(const {key,expected} of changes){
    if(expected!==undefined && cache.has(key) && JSON.stringify(expected)!==JSON.stringify(cache.get(key))) throw new Error(`The ${key} records changed since this page was opened. Reload before saving.`);
  }
  const expectedChanges=changes.map(({key,value})=>({key,expected:cache.has(key)?cache.get(key):null,payload:value}));
  const operation=writeQueue.catch(() => undefined).then(async () => {
    if (accessToken !== token || !initialized) throw new Error('ERP session changed during save.');
    try {
      await rpc('erp_commit_ui_state_batch',{p_changes:expectedChanges},{accessToken:token});
    } catch(error) {
      if (!isMissingIntegrityRpc(error,'erp_commit_ui_state_batch')) throw error;
      // Backward compatible only. A failure can leave a partial handoff.
      for(const item of expectedChanges) {
        await rpc('erp_put_ui_state',{p_storage_key:item.key,p_payload:item.payload},{accessToken:token});
        cache.set(item.key,item.payload);
        emit('erp-cloud-change',{type:'confirmed-write',key:item.key});
      }
      return;
    }
    for(const item of expectedChanges) {
      cache.set(item.key,item.payload);
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
