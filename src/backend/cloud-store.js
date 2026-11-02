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
}

export function isCloudStoreReady() {
  return initialized;
}

export async function initializeCloudStore(token) {
  if (!backendConfigured) {
    throw new Error('Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to .env.');
  }
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
    Object.assign(error, {failures: [...writeErrors]});
    throw error;
  }
}

export function exportCloudSnapshot() {
  return Object.fromEntries(cache.entries());
}

/** Commit related UI sections together. Cache is updated only after DB success.
 * Expected payloads provide optimistic concurrency for the new process screens. */
export async function commitProcessChanges(changes, expected, action = 'save') {
  if (!initialized || !accessToken) throw new Error('Your session is not ready. Sign in again before saving.');
  await flushCloudWrites();
  await rpc('erp_commit_process', {p_changes: changes, p_expected: expected, p_action: action}, {accessToken});
  for (const [key, value] of Object.entries(changes)) cache.set(key, value);
  emit('erp-cloud-change', {type: 'process-commit'});
  emit('erp-storage-saved', {key: Object.keys(changes).join(', ')});
}

export async function nextProcessNumber(type, prefix, year) {
  if (!initialized || !accessToken) throw new Error('Sign in before creating a document.');
  return rpc('erp_next_process_no', {p_document_type: type, p_prefix: prefix, p_financial_year: year}, {accessToken});
}
