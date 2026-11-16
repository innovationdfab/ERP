import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {temporaryPasswordIssue} from '../src/employee-password-policy.js';
const get=p=>readFileSync(new URL(`../${p}`,import.meta.url),'utf8');

test('employee temporary password supports explicit secure entry or an empty server-managed default',()=>{
  assert.equal(temporaryPasswordIssue('','',{allowEmpty:true}),'');
  assert.match(temporaryPasswordIssue('','mismatch',{allowEmpty:true}),/12/);
  assert.match(temporaryPasswordIssue('short','short'),/12/);
  assert.match(temporaryPasswordIssue('twelvecharslong','twelvecharslong'),/letter and a number/);
  assert.match(temporaryPasswordIssue('AnIndividualPassword2026','IncorrectPassword2026'),/match/);
  assert.equal(temporaryPasswordIssue('AnIndividualPassword2026','AnIndividualPassword2026'),'');
});
test('employee add and edit use protected Auth password controls, not ERP record columns',()=>{
  const ui=get('src/admin-control.jsx'), api=get('src/admin-api.js');
  assert.match(ui,/STEP 3 · INITIAL LOGIN PASSWORD/);
  assert.match(ui,/EMPLOYEE PASSWORD RESET/);
  assert.match(ui,/Confirm password/);
  assert.match(ui,/temporaryPasswordIssue/);
  assert.match(ui,/setEmployeePassword\(\{\.\.\.blankPasswordFields\}\)/);
  assert.match(api,/export const resetEmployeeLogin=\(user_id,password=''/);
  assert.match(api,/\.\.\.\(password\?\{password\}:\{\}\)/);
  assert.doesNotMatch(api,/p_password|password.*erp_admin_save_user/);
});
test('Edge Function validates an individual password, requires admin, and rolls back failed new employee provisioning',()=>{
  const fn=get('supabase/functions/erp-admin-invite/index.ts');
  assert.match(fn,/validPersonalPassword\(suppliedPassword\)/);
  assert.match(fn,/caller\.rpc\('erp_admin_is_admin'\)/);
  assert.match(fn,/auth\.admin\.createUser/);
  assert.match(fn,/auth\.admin\.updateUserById/);
  assert.match(fn,/auth\.admin\.deleteUser\(created\.user\.id\)/);
  assert.match(fn,/app_metadata: \{ \[initialFlag\]: true \}/);
  assert.doesNotMatch(fn,/return respond\(200, .*password:\s*suppliedPassword/);
});
test('signed-out login has no Admin button, but authenticated ERP header keeps Admin',()=>{
  const main=get('src/main.jsx');
  assert.doesNotMatch(main,/Admin Control Center · view without login/);
  assert.doesNotMatch(main,/className="dfab-admin-preview-button"/);
  assert.match(main,/className=\{`erp-top-admin-btn/);
  assert.match(main,/goToPage\('Admin Control'\)/);
});
test('Supabase Auth and Edge Function errors are surfaced meaningfully',()=>{
  const helper=get('src/backend/supabase-rest.js');
  assert.match(helper,/Incorrect email or password/);
  assert.match(helper,/edgeFunction \? detail/);
  assert.match(helper,/if \(!accessToken\) throw new Error\('Sign in before inviting a user/);
});
