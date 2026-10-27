import { backendConfigured, rpc } from './supabase-rest.js';

const cache = new Map();
let accessToken = '';
let initialized = false;
let writeQueue = Promise.resolve();

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
  window.dispatchEvent(new CustomEvent('erp-cloud-ready'));
  return cache.size;
}

export function readCloudValue(key, fallback) {
  return cache.has(key) ? cache.get(key) : fallback;
}

export function writeCloudValue(key, value) {
  cache.set(key, value);
  if (!initialized || !accessToken) return true;
  writeQueue = writeQueue
    .then(() => rpc('erp_put_ui_state', { p_storage_key: key, p_payload: value }, { accessToken }))
    .catch((error) => {
      window.dispatchEvent(new CustomEvent('erp-storage-error', { detail: `Database save failed: ${error.message}` }));
    });
  return true;
}

export function removeCloudValue(key) {
  cache.delete(key);
  if (!initialized || !accessToken) return false;
  writeQueue = writeQueue
    .then(() => rpc('erp_delete_ui_state', { p_storage_key: key }, { accessToken }))
    .catch((error) => {
      window.dispatchEvent(new CustomEvent('erp-storage-error', { detail: `Database delete failed: ${error.message}` }));
    });
  return true;
}

export async function flushCloudWrites() {
  await writeQueue;
}

export function exportCloudSnapshot() {
  return Object.fromEntries(cache.entries());
}
