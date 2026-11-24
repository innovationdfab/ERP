import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=p=>fs.readFileSync(new URL(`../${p}`,import.meta.url),'utf8');
const ui=read('src/admin-control.jsx');
const migration=read('supabase/ERP_ADMIN_DEPARTMENT_ROLES_SAFE.sql');
test('Add/Edit login options use server roles, not hardcoded department names',()=>{
 assert.match(ui,/data\.roles\.filter\(r=>r\.active/);
 assert.match(ui,/setInvitation\(v=>\(\{\.\.\.v,role_ids:id\?\[id\]:\[\]\}\)\)/);
 assert.match(ui,/setUser\(v=>\(\{\.\.\.v,role_ids:e\.target\.value\?\[e\.target\.value\]:\[\]\}\)\)/);
});
test('Admin role summary displays the real permission matrix',()=>{
 assert.match(ui,/data\?\.rights\|\|\[\]/);
 assert.match(ui,/loginRoleRights\.filter\(entry=>entry\.can_view\)/);
 assert.match(ui,/Only Administrator exists in Supabase/);
});
test('migration safely preserves existing roles and role rights',()=>{
 assert.match(migration,/ON CONFLICT \(organization_id,code\) DO NOTHING/i);
 assert.match(migration,/ON CONFLICT \(role_id,page\) DO NOTHING/i);
 assert.doesNotMatch(migration,/\bDELETE\s+FROM\b/i);
 assert.doesNotMatch(migration,/\bUPDATE\s+public\.erp_roles\b/i);
 assert.doesNotMatch(migration,/\bSYSTEM\.ADMIN\s*'\s*\)/i);
});
test('role default matrix does not automatically grant destructive or approval rights',()=>{
 assert.match(migration,/SELECT r\.id,c\.page,true,true,true,false,false,false/);
 assert.match(migration,/JOIN public\.erp_permissions perm ON perm\.code IN \('ERP\.VIEW','ERP\.EDIT'\)/);
 assert.match(migration,/CREATE TEMP TABLE _erp_new_department_roles/);
});
