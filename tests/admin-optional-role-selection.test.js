import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const src=readFileSync(new URL('../src/admin-control.jsx',import.meta.url),'utf8');
const edge=readFileSync(new URL('../supabase/functions/erp-admin-invite/index.ts',import.meta.url),'utf8');
test('administrator checkbox is optional and separated from employee role selection',()=>{
 assert.match(src,/Mark as Administrator \(optional\)/);
 assert.match(src,/checked=\{isAdminRoleSelected\(invitation\.role_ids\)\}/);
 assert.match(src,/!isAdminRoleSelected\(invitation\.role_ids\)&&<label className="admin-invite-role-select"/);
 assert.match(src,/employeeRoles\.map\(r=>/);
 assert.match(src,/role_ids:id\?\[id\]:\[\]/);
});
test('administrator and employee creation use the same protected original provisioning handler',()=>{
 assert.match(src,/inviteUser\(\{\.\.\.invitation/);
 assert.match(src,/checked\?\[adminRole\.id\]:\[\]/);
 assert.match(edge,/requestedAdmin/);
 assert.match(edge,/erp_admin_provision_employee/);
 assert.match(edge,/inviteUserByEmail/);
 assert.match(edge,/createUser/);
});
