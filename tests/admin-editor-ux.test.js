import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const src=readFileSync(new URL('../src/admin-control.jsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../src/admin-control.css',import.meta.url),'utf8');
const api=readFileSync(new URL('../src/admin-api.js',import.meta.url),'utf8');

test('employee editor has separate full-width details, permissions and login credential sections',()=>{
 for(const id of ['admin-employee-details-heading','admin-employee-access-heading','admin-employee-credentials-heading'])assert.ok(src.includes(id));
 assert.match(src,/admin-employee-workspace/);
 assert.match(src,/admin-workspace-editing/);
 assert.match(css,/\.admin-simple \.admin-workspace-editing>\.admin-card:not\(\.admin-edit-card\)\{display:none\}/);
 assert.match(css,/\.admin-simple \.admin-employee-fields\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
});
test('employee create, edit, cancel and reset actions still call actual Supabase-backed handlers',()=>{
 for(const fn of ['beginEmployeeInvite','selectUser','closeEmployeeEditor','sendInvitation','saveUserForm','resetCustomPassword','disableEmployee','resetDepartmentLogins']) assert.ok(src.includes(fn));
 assert.match(src,/onClick=\{inviting\?sendInvitation:saveUserForm\}/);
 assert.match(src,/onClick=\{resetCustomPassword\}/);
 assert.match(src,/onClose=\{closeEmployeeEditor\}/);
 assert.match(api,/export const inviteUser=.*invokeFunction/);
 assert.match(api,/export const resetEmployeeLogin=.*invokeFunction/);
 assert.match(api,/export const saveUser=.*erp_admin_save_user/);
});
test('other Admin editors use the same focused layout without changing business routes',()=>{
 assert.match(src,/department\?'admin-workspace-editing'/);
 assert.match(src,/role\?'admin-workspace-editing'/);
 assert.match(src,/template\?'admin-workflow-editing'/);
 assert.match(src,/onClose=\{\(\)=>setDepartment\(null\)\}/);
 assert.match(src,/onClose=\{\(\)=>setRole\(null\)\}/);
 assert.match(css,/\.admin-simple \.admin-workflow-editing>\.admin-card:first-child\{display:none\}/);
});
test('admin permissions, secured password handling, and backend write paths remain unchanged',()=>{
 assert.match(src,/isAdminRoleSelected\(user\.role_ids\|\|\[\]\)/);
 assert.match(src,/temporaryPasswordIssue/);
 assert.match(src,/askConfirmation/);
 assert.match(src,/publishTemplate/);
 assert.match(src,/deleteRole/);
 assert.doesNotMatch(api,/p_password|password.*erp_admin_save_user/);
});
