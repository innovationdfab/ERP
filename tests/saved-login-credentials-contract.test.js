import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = file => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8');
test('non-admin accounts use the exact explicitly confirmed password from Add Login', () => {
  const form=read('src/admin-control.jsx');
  const fn=read('supabase/functions/erp-admin-invite/index.ts');
  assert.match(form,/if\(!adminInvite\)\{const issue=passwordIssue\(employeePassword\);/);
  assert.match(fn,/if \(!requestedAdmin && !suppliedPassword\)/);
  assert.match(fn,/createUser\(\{ email, password: suppliedPassword/);
  assert.match(fn,/app_metadata: \{ \[initialFlag\]: true \}/);
});
test('admin role gets individual invitation to a configured and allowlisted ERP URL', () => {
  const fn=read('supabase/functions/erp-admin-invite/index.ts');
  assert.match(fn,/if \(requestedAdmin && suppliedPassword\)/);
  assert.match(fn,/allowedOrigins\.includes\(parsed\.origin\)/);
  assert.match(fn,/inviteUserByEmail\(email, \{ data: \{ full_name: name \}, redirectTo: invitationRedirect \}\)/);
  assert.match(fn,/caller\.rpc\('erp_admin_is_admin'\)/);
});
test('invitation callback sets personal password with short-lived verified token before regular sign in', () => {
  const main=read('src/main.jsx');
  const api=read('src/backend/supabase-rest.js');
  assert.match(main,/fragment\.get\('type'\)!=='invite'/);
  assert.match(main,/window\.history\.replaceState/);
  assert.match(main,/getAuthUser\(invitationToken\)/);
  assert.match(main,/passwordSetup\.invitation\)await setInvitedAuthPassword/);
  assert.match(api,/export async function setInvitedAuthPassword/);
  assert.match(main,/await signInWithPassword\(email,loginValues\.password\)/);
});
