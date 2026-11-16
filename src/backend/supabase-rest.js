/// <reference types="vite/client" />
/**
 * Lightweight Supabase REST/Auth helper with zero runtime dependencies.
 * Used by the ERP cloud persistence and authentication layers. Browser-local ERP record persistence is disabled.
 */

/** @type {Record<string, string | boolean>} */
const env = import.meta.env || {};
const url = String(env.VITE_SUPABASE_URL || '').trim().replace(/\/$/, '');
const publishableKey = String(
  env.VITE_SUPABASE_PUBLISHABLE_KEY || env.VITE_SUPABASE_ANON_KEY || ''
).trim();

const hasPlaceholder =
  !url ||
  !publishableKey ||
  /YOUR_PROJECT_ID|YOUR_SUPABASE/i.test(url) ||
  /YOUR_PROJECT_ID|YOUR_SUPABASE/i.test(publishableKey);

export const backendConfigured = !hasPlaceholder;

function requireConfig() {
  if (hasPlaceholder) {
    throw new Error(
      'Supabase is not configured yet. Open .env and replace the Project URL and Publishable key placeholders, then restart npm run dev.'
    );
  }
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)) {
    throw new Error('VITE_SUPABASE_URL is invalid. Copy the exact Project URL from Supabase Connect / Settings > API Keys.');
  }
}

function headers(accessToken, extra = {}) {
  /** @type {Record<string, string>} */
  const result = {
    apikey: publishableKey,
    'Content-Type': 'application/json',
    ...extra,
  };
  // Publishable keys identify the browser app and belong in `apikey`.
  // Only a real signed-in user JWT belongs in Authorization.
  if (accessToken) result.Authorization = `Bearer ${accessToken}`;
  return result;
}

async function request(path, options = {}) {
  requireConfig();
  // A stalled network request must not leave ERP forms waiting indefinitely.
  // Abort does not guarantee a previously submitted database write was rolled
  // back. Callers must reconcile state after any uncertain write outcome.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);
  let response;
  let bodyText;
  try {
    response = await fetch(`${url}${path}`, { ...options, signal: controller.signal });
    bodyText = await response.text();
  } catch (error) {
    if (controller.signal.aborted) {
      throw new Error('Supabase did not respond within 30 seconds. For a save, reload and confirm whether the document exists before retrying.');
    }
    throw new Error(
      `Cannot reach Supabase. Check your connection and configured project URL. For a save, verify whether it completed before retrying. (${error?.message || 'network error'})`
    );
  } finally {
    clearTimeout(timeout);
  }
  const body = bodyText ? (() => {
    try { return JSON.parse(bodyText); } catch { return bodyText; }
  })() : null;
  if (!response.ok) {
    const detail = body?.message || body?.error_description || body?.error || `Request failed (${response.status})`;
    const identityLogin = path.startsWith('/auth/v1/token?grant_type=password');
    const edgeFunction = path.startsWith('/functions/v1/');
    const message = identityLogin && /invalid login credentials|invalid email or password/i.test(String(detail))
      ? 'Incorrect email or password. Check the employee credentials configured in Admin.'
      : edgeFunction ? detail
      : response.status === 401 ? 'Supabase session expired or is invalid. Sign in again.'
      : response.status === 403 ? 'Permission denied by Supabase. Contact your ERP administrator.'
      : detail;
    throw new Error(String(message));
  }
  return body;
}

export async function signInWithPassword(email, password) {
  if (!email?.trim() || !password) throw new Error('Email and password are required.');
  return request('/auth/v1/token?grant_type=password', {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({ email: email.trim(), password }),
  });
}


export async function getAuthUser(accessToken) {
  if (!accessToken) throw new Error('No active login session.');
  return request('/auth/v1/user', { headers: headers(accessToken) });
}

export async function refreshSession(refreshToken) {
  if (!refreshToken) throw new Error('No refresh token is available.');
  return request('/auth/v1/token?grant_type=refresh_token', {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
}

export async function signOut(accessToken) {
  if (!accessToken) return;
  await request('/auth/v1/logout', { method: 'POST', headers: headers(accessToken) });
}

/** @param {{accessToken?: string, select?: string, query?: string}} [options] */
export async function selectRows(table, options = {}) {
  const { accessToken, select = '*', query = '' } = options;
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  const suffix = query ? `&${query.replace(/^&/, '')}` : '';
  return request(`/rest/v1/${table}?select=${encodeURIComponent(select)}${suffix}`, {
    headers: headers(accessToken),
  });
}

/** @param {{accessToken?: string, returnRows?: boolean}} [options] */
export async function insertRows(table, rows, options = {}) {
  const { accessToken, returnRows = true } = options;
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!Array.isArray(rows) || rows.length === 0) throw new Error('At least one row is required.');
  return request(`/rest/v1/${table}`, {
    method: 'POST',
    headers: headers(accessToken, { Prefer: returnRows ? 'return=representation' : 'return=minimal' }),
    body: JSON.stringify(rows),
  });
}

/** @param {{accessToken?: string}} [options] */
export async function updateRows(table, values, filterQuery, options = {}) {
  const { accessToken } = options;
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!filterQuery) throw new Error('A filter is required for updates.');
  return request(`/rest/v1/${table}?${filterQuery}`, {
    method: 'PATCH',
    headers: headers(accessToken, { Prefer: 'return=representation' }),
    body: JSON.stringify(values),
  });
}

/** @param {{accessToken?: string, onConflict?: string, returnRows?: boolean}} [options] */
export async function upsertRows(table, rows, options = {}) {
  const { accessToken, onConflict = '', returnRows = true } = options;
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!Array.isArray(rows) || rows.length === 0) throw new Error('At least one row is required.');
  const conflict = onConflict ? `?on_conflict=${encodeURIComponent(onConflict)}` : '';
  return request(`/rest/v1/${table}${conflict}`, {
    method: 'POST',
    headers: headers(accessToken, { Prefer: `${returnRows ? 'return=representation' : 'return=minimal'},resolution=merge-duplicates` }),
    body: JSON.stringify(rows),
  });
}

/** @param {{accessToken?: string}} [options] */
export async function deleteRows(table, filterQuery, options = {}) {
  const { accessToken } = options;
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!filterQuery) throw new Error('A filter is required for deletes.');
  return request(`/rest/v1/${table}?${filterQuery}`, {
    method: 'DELETE',
    headers: headers(accessToken, { Prefer: 'return=minimal' }),
  });
}

/** @param {{accessToken?: string}} [options] */
export async function rpc(functionName, args = {}, options = {}) {
  const { accessToken } = options;
  if (!/^[a-z0-9_]+$/i.test(functionName)) throw new Error('Invalid function name.');
  return request(`/rest/v1/rpc/${functionName}`, {
    method: 'POST',
    headers: headers(accessToken),
    body: JSON.stringify(args),
  });
}

/** Supabase Edge Functions run with a server-side service key; never expose it in Vite. */
/** @param {{accessToken?: string}} [options] */
export async function invokeFunction(name, payload, options = {}) {
  const {accessToken} = options;
  if (!/^[a-z0-9-]+$/i.test(name)) throw new Error('Invalid function name.');
  if (!accessToken) throw new Error('Sign in before inviting a user.');
  return request(`/functions/v1/${name}`, {
    method:'POST', headers:headers(accessToken), body:JSON.stringify(payload),
  });
}
