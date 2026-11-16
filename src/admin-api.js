import { rpc, invokeFunction } from './backend/supabase-rest.js';

let adminToken = '';
export function setAdminToken(token='') { adminToken=token; }
function mustToken(){ if(!adminToken) throw new Error('ERP session expired. Sign in again.');return adminToken; }
const call=(name,args={})=>rpc(name,args,{accessToken:mustToken()});
export async function loadMyAccess() {
  try {
    return await call('erp_admin_my_access');
  } catch (error) {
    if (/erp_admin_my_access|PGRST202|schema cache|could not find the function/i.test(error?.message || '')) {
      throw new Error('Admin Control is not installed in this Supabase project. Run supabase/ERP_ADMIN_CONTROL.sql after its prerequisite migrations in the Supabase SQL Editor, then refresh the PostgREST schema cache. The local Admin Preview does not require login.');
    }
    throw error;
  }
}
export const loadWorkflowRuntime=()=>call('erp_admin_active_workflow');
export const loadAdminDashboard=()=>call('erp_admin_dashboard');
export const saveDepartment=(department)=>call('erp_admin_save_department',{
  p_id:department.id||null,p_code:department.code,p_name:department.name,
  p_cost_center:department.cost_center||null,p_active:department.active!==false,
});
export const saveRole=(role)=>call('erp_admin_save_role',{
  p_id:role.id||null,p_code:role.code,p_name:role.name,p_description:role.description||'',
  p_active:role.active!==false,p_rights:role.rights||[],
});
export const saveUser=(user)=>call('erp_admin_save_user',{
  p_user_id:user.user_id,p_department_id:user.department_id||null,
  p_display_name:user.display_name,p_active:user.active!==false,p_role_ids:user.role_ids||[],
});
export const inviteUser=async ({email,name,department_id,role_ids,password=''}) => invokeFunction('erp-admin-invite',{
  action:'create',email,name,department_id:department_id||null,role_ids:role_ids||[],
  ...(password?{password}:{}),
},{accessToken:mustToken()});
// Only the secured admin Edge Function can alter Supabase Auth credentials.
export const resetEmployeeLogin=(user_id,password='')=>invokeFunction('erp-admin-invite', {action:'reset',user_id,...(password?{password}:{})},{accessToken:mustToken()});
export const resetEmployeeLogins=(user_ids)=>invokeFunction('erp-admin-invite', {action:'bulk-reset',user_ids},{accessToken:mustToken()});

export const saveTemplate=(template)=>call('erp_admin_save_template',{
  p_id:template.id||null,p_name:template.name,p_description:template.description||'',
  p_edges:template.edges||[],p_expected_version:template.id?template.version:null,
});
export const publishTemplate=(template)=>call('erp_admin_publish_template',{
  p_id:template.id,p_expected_version:template.version,
});
export const unpublishTemplate=()=>call('erp_admin_reset_workflow');
export const registerStorage=(mapping)=>call('erp_admin_map_storage',{
  p_key:mapping.storage_key,p_page:mapping.page_name,p_key_index:Number(mapping.record_key_index)||0,p_status_index:Number.isInteger(Number(mapping.status_index))?Number(mapping.status_index):-1,
});

// Safe administrator removal operations: all authorization and dependency checks live in PostgreSQL.
export const deleteDraftTemplate=(template)=>call('erp_admin_delete_template',{p_id:template.id,p_expected_version:template.version});
export const deleteDepartment=(id)=>call('erp_admin_delete_department',{p_id:id});
export const deleteRole=(id)=>call('erp_admin_delete_role',{p_id:id});
export const unmapStorage=(key)=>call('erp_admin_unmap_storage',{p_key:key});
