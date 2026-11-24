import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read = file => readFileSync(new URL(`../${file}`,import.meta.url),'utf8');
test('Add Login only requires email, role and password and has optional name',()=>{
 const s=read('src/admin-control.jsx');
 assert.match(s,/blankInvitation=\{email:'',name:'',role_ids:\[\]\}/);
 assert.match(s,/Name \(optional\)/);
 assert.match(s,/inviteUser\(\{email,name:trim\(invitation.name\),role_ids:invitation.role_ids,password:employeePassword.password\}\)/);
});
test('Edge Function derives a display name and does not mandate a department',()=>{
 const s=read('supabase/functions/erp-admin-invite/index.ts');
 assert.match(s,/const suppliedName = typeof body.name === 'string'/);
 assert.match(s,/const departmentId = null/);
 assert.match(s,/Enter a valid email address and select exactly one role/);
 assert.doesNotMatch(s,/Valid employee email, name, department and role are required/);
});
test('Old deployed Edge Function validation gives explicit redeploy instruction',()=>{
 const s=read('src/admin-api.js');
 assert.match(s,/Supabase is running an outdated erp-admin-invite Edge Function/);
 assert.match(s,/Redeploy supabase\/functions\/erp-admin-invite\/index.ts/);
});
