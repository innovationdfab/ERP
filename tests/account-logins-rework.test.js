import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=path=>readFileSync(new URL(path,import.meta.url),'utf8');
const ui=read('../src/admin-control.jsx');
const api=read('../src/admin-api.js');
const service=read('../supabase/functions/erp-admin-invite/index.ts');
test('Add Login requires email role and explicit password',()=>{
 assert.match(ui,/Enter a valid email and choose one role/);
 assert.match(ui,/passwordIssue\(employeePassword\)/);
 assert.match(ui,/inviteUser\(\{email,role_ids:invitation\.role_ids,password:employeePassword\.password\}\)/);
 assert.match(ui,/Create login/);
});
test('Admin and employee share explicit password creation in Auth',()=>{
 assert.match(service,/auth\.admin\.createUser\(/);
 assert.match(service,/email_confirm: true/);
 assert.match(service,/password: suppliedPassword/);
 assert.doesNotMatch(service,/inviteUserByEmail\(/);
 assert.doesNotMatch(service,/action === 'bulk-reset'/);
});
test('Role is saved in ERP and credentials remain solely in Auth',()=>{
 assert.match(service,/erp_admin_provision_employee/);
 assert.match(api,/action:'create'/);
 assert.doesNotMatch(api,/saveUser=.*password/);
});
test('Delete revokes access and Auth login, without deleting ERP records',()=>{
 assert.match(ui,/Delete login access/);
 assert.match(api,/action:'revoke'/);
 assert.match(service,/ban_duration: '876000h'/);
 assert.match(service,/p_active:false, p_role_ids:\[\]/);
 assert.doesNotMatch(service,/auth\.admin\.deleteUser\(id\)/);
});
test('Edit supports role change, explicit password reset and restoring disabled login',()=>{
 assert.match(ui,/Save role and access/);
 assert.match(ui,/Update password/);
 assert.match(api,/action:'reset'/);
 assert.match(api,/action:'restore'/);
 assert.match(service,/ban_duration: 'none'/);
});
