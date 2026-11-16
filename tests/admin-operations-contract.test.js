import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
const root=new URL('..',import.meta.url).pathname;
const read=p=>readFileSync(join(root,p),'utf8');
const sql=read('supabase/ERP_ADMIN_OPERATIONS_V2.sql');
const api=read('src/admin-api.js');
const ui=read('src/admin-control.jsx');
const shell=read('src/main.jsx');
const preview=read('src/admin-preview.jsx');

test('admin management functions refuse unauthenticated and non-admin writes',()=>{
 for(const name of ['erp_admin_delete_template','erp_admin_delete_department','erp_admin_delete_role','erp_admin_unmap_storage']){
  assert.match(sql,new RegExp(`create or replace function public\\.${name}\\(`));
  assert.match(sql,new RegExp(`revoke all on function public\\.${name}\\([^;]+from PUBLIC,anon,authenticated;`));
  assert.match(api,new RegExp(`'${name}'`));
 }
 assert.equal((sql.match(/if not public\.erp_admin_is_admin\(\)/g)||[]).length,4);
 assert.match(sql,/to authenticated;/);
});
test('admin deletion protects published flow, assigned staff, system roles and saved data',()=>{
 assert.match(sql,/v_template\.status<>'draft'/);
 assert.match(sql,/p_expected_version is distinct from v_template\.version/);
 assert.match(sql,/exists\(select 1 from public\.erp_profiles where department_id=p_id/);
 assert.match(sql,/v_role\.system_role or v_role\.code='ADMIN'/);
 assert.match(sql,/exists\(select 1 from public\.erp_user_roles where role_id=p_id/);
 assert.match(sql,/erp_ui_state where storage_key=p_key/);
 assert.match(sql,/erp_ui_records where storage_key=p_key/);
});
test('all destructive administrator controls require in-app confirmation',()=>{
 for(const fn of ['removeTemplate','removeDepartment','removeRole','disableEmployee','removeStorageMap']){
  assert.match(ui,new RegExp(`const ${fn}=async`));
 }
 assert.equal((ui.match(/if\(!await askConfirmation\(/g)||[]).length>=5,true);
 assert.doesNotMatch(ui,/window\.confirm|window\.alert/);
});
test('signed out admin entry is view-only while signed-in admin gets control panel',()=>{
 assert.match(shell,/if\(!authenticated && adminPreviewOpen\)return <AdminPreview publicMode=/);
 assert.match(preview,/if\(publicMode\) return/);
 assert.match(preview,/No company database information is exposed/);
 assert.match(shell,/if\(activePage==='Admin Control'&&\!ctx\.adminAccess\?\.is_admin\)/);
 assert.match(shell,/if\(activePage==='Admin Control'\|\|\['Users','User Roles','Role Permissions'\]/);
});
test('employee archive uses server controlled save not Auth credential disclosure',()=>{
 assert.match(ui,/saveUser\(\{\.\.\.p,active:false,role_ids:\[\]\}\)/);
 assert.match(read('supabase/ERP_ADMIN_CONTROL.sql'),/USER_ACCESS_SAVED/);
 assert.doesNotMatch(ui,/service_role|SUPABASE_SERVICE_ROLE_KEY/);
});
