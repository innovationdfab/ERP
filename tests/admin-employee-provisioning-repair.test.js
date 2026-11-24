import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const sql=readFileSync(new URL('../supabase/ERP_ADMIN_EMPLOYEE_PROVISIONING_REPAIR.sql',import.meta.url),'utf8');
const edge=readFileSync(new URL('../supabase/functions/erp-admin-invite/index.ts',import.meta.url),'utf8');
const ui=readFileSync(new URL('../src/admin-control.jsx',import.meta.url),'utf8');
test('Admin provisioning SQL is additive, admin-gated and verifies actual Auth email',()=>{
 assert.match(sql,/CREATE OR REPLACE FUNCTION public\.erp_admin_provision_employee/i);
 assert.match(sql,/NOT public\.erp_admin_is_admin\(\)/);
 assert.match(sql,/FROM auth\.users WHERE id=p_user_id/i);
 assert.match(sql,/v_auth_email<>lower\(trim\(p_email\)\)/);
 assert.match(sql,/ON CONFLICT\(user_id\) DO NOTHING/i);
 assert.match(sql,/PERFORM public\.erp_admin_save_user/i);
 assert.match(sql,/REVOKE ALL ON FUNCTION.*FROM PUBLIC,anon/i);
 assert.doesNotMatch(sql,/\bDROP (?:TABLE|SCHEMA)\b|\bTRUNCATE\b|\bDELETE FROM\b/i);
});
test('Create Login uses the atomic ERP Admin provisioning RPC and reports exact validation errors',()=>{
 assert.match(edge,/caller\.rpc\('erp_admin_provision_employee'/);
 assert.match(edge,/p_email: email, p_display_name: name/);
 assert.match(edge,/ERP profile or role assignment failed:/);
 assert.match(ui,/Complete all required fields: full name, valid work email, department and at least one role/);
 assert.match(ui,/The password and confirmation do not match|passwordIssue\(employeePassword\)/);
});
