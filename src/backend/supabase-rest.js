/**
 * Lightweight Supabase REST/Auth helper with zero runtime dependencies.
 * Used by the ERP cloud persistence and authentication layers. Browser-local ERP record persistence is disabled.
 */

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
  let response;
  try {
    response = await fetch(`${url}${path}`, options);
  } catch (error) {
    throw new Error(
      `Cannot reach Supabase. Check VITE_SUPABASE_URL, internet access, and restart the Vite dev server after editing .env. (${error?.message || 'network error'})`
    );
  }
  const bodyText = await response.text();
  const body = bodyText ? (() => {
    try { return JSON.parse(bodyText); } catch { return bodyText; }
  })() : null;

  if (!response.ok) {
    const message = body?.message || body?.error_description || body?.error || `Request failed (${response.status})`;
    throw new Error(message);
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

export async function selectRows(table, { accessToken, select = '*', query = '' } = {}) {
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  const suffix = query ? `&${query.replace(/^&/, '')}` : '';
  return request(`/rest/v1/${table}?select=${encodeURIComponent(select)}${suffix}`, {
    headers: headers(accessToken),
  });
}

export async function insertRows(table, rows, { accessToken, returnRows = true } = {}) {
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!Array.isArray(rows) || rows.length === 0) throw new Error('At least one row is required.');
  return request(`/rest/v1/${table}`, {
    method: 'POST',
    headers: headers(accessToken, { Prefer: returnRows ? 'return=representation' : 'return=minimal' }),
    body: JSON.stringify(rows),
  });
}

export async function updateRows(table, values, filterQuery, { accessToken } = {}) {
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!filterQuery) throw new Error('A filter is required for updates.');
  return request(`/rest/v1/${table}?${filterQuery}`, {
    method: 'PATCH',
    headers: headers(accessToken, { Prefer: 'return=representation' }),
    body: JSON.stringify(values),
  });
}

export async function upsertRows(table, rows, { accessToken, onConflict = '', returnRows = true } = {}) {
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!Array.isArray(rows) || rows.length === 0) throw new Error('At least one row is required.');
  const conflict = onConflict ? `?on_conflict=${encodeURIComponent(onConflict)}` : '';
  return request(`/rest/v1/${table}${conflict}`, {
    method: 'POST',
    headers: headers(accessToken, { Prefer: `${returnRows ? 'return=representation' : 'return=minimal'},resolution=merge-duplicates` }),
    body: JSON.stringify(rows),
  });
}

export async function deleteRows(table, filterQuery, { accessToken } = {}) {
  if (!/^[a-z0-9_]+$/i.test(table)) throw new Error('Invalid table name.');
  if (!filterQuery) throw new Error('A filter is required for deletes.');
  return request(`/rest/v1/${table}?${filterQuery}`, {
    method: 'DELETE',
    headers: headers(accessToken, { Prefer: 'return=minimal' }),
  });
}

export async function rpc(functionName, args = {}, { accessToken } = {}) {
  if (!/^[a-z0-9_]+$/i.test(functionName)) throw new Error('Invalid function name.');
  return request(`/rest/v1/rpc/${functionName}`, {
    method: 'POST',
    headers: headers(accessToken),
    body: JSON.stringify(args),
  });
}
