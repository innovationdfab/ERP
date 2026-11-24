import { rpc, invokeFunction } from './backend/supabase-rest.js';

let adminToken = '';
export function setAdminToken(token='') { adminToken=token; }
function mustToken(){ if(!adminToken) throw new Error('ERP session expired. Sign in again.');return adminToken; }
// Diagnose Admin-only transport failures without altering the shared ERP API layer.
// Never automatically replay writes: a dropped connection may occur after commit.
function explainAdminNetworkFailure(error, operation) {
  const message=String(error?.message||'Unknown network error');
  if(!/Cannot reach Supabase|Failed to fetch|NetworkError|load failed|did not respond within 30 seconds/i.test(message)) return error;
  const url=String(import.meta.env?.VITE_SUPABASE_URL||'').trim();
  const host=/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url)?url.replace(/\/$/,''):'not configured correctly';
  const endpoint=operation==='erp-admin-invite'?'Edge Function erp-admin-invite':`database function ${operation}`;
  return new Error(`Cannot connect to Supabase while calling ${endpoint}. Configured project: ${host}. Check your deployed VITE_SUPABASE_URL and publishable key, browser Network tab, and project availability. For employee login creation, also check the Edge Function deployment and CORS preflight (OPTIONS) for your Vercel site. This is a network/configuration failure, not evidence that SQL is missing. If you were saving, refresh Saved logins to confirm whether the operation completed before retrying.`);
}
const adminRequest=async(operation,fn)=>{try{return await fn()}catch(error){throw explainAdminNetworkFailure(error,operation)}};
const call=async(name,args={})=>{const result=await adminRequest(name,()=>rpc(name,args,{accessToken:mustToken()}));if(/erp_admin_(save|delete|publish|reset_workflow|map_storage|unmap_storage)/.test(name)&&typeof window!=='undefined')window.dispatchEvent(new CustomEvent('erp-operation-feedback',{detail:{title:/delete|unmap/.test(name)?'Deleted':/publish/.test(name)?'Published':'Saved'}}));return result;};
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
export const inviteUser=async ({email,name,department_id,role_ids,password=''}) => adminRequest('erp-admin-invite',()=>invokeFunction('erp-admin-invite',{
  action:'create',email,name,department_id:department_id||null,role_ids:role_ids||[],
  ...(password?{password}:{}),
},{accessToken:mustToken()}));
// Only the secured admin Edge Function can alter Supabase Auth credentials.
export const resetEmployeeLogin=(user_id,password='')=>adminRequest('erp-admin-invite',()=>invokeFunction('erp-admin-invite', {action:'reset',user_id,...(password?{password}:{})},{accessToken:mustToken()}));
export const resetEmployeeLogins=(user_ids)=>adminRequest('erp-admin-invite',()=>invokeFunction('erp-admin-invite', {action:'bulk-reset',user_ids},{accessToken:mustToken()}));

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

export const loadWorkspaceActivity=()=>call('erp_workspace_activity');
export const loadWorkspaceTransactions=day=>call('erp_workspace_transactions',{p_day:day});
