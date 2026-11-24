/** Clarify whether an error came from Supabase Auth or subsequent ERP initialization. */
export function loginFailureMessage(error,{credentialsVerified=false,stage='authentication'}={}) {
  const detail=String(error?.detail||error?.message||'Unknown error');
  const status=Number(error?.status)||0;
  const missingRpc=/PGRST202|could not find the function|schema cache|function .* does not exist/i.test(detail);
  if(!credentialsVerified){
    if(status===404)return 'Supabase Auth endpoint returned 404. Confirm the local VITE_SUPABASE_URL is the same project as your saved employee accounts, then restart the development server.';
    return error?.message||'Unable to sign in. Verify your account email and password.';
  }
  if(missingRpc || (status===404 && stage!=='authentication')){
    return `Your email and password were accepted, but ${stage} cannot open because a required Supabase database function is unavailable (404). Confirm the existing ERP/Admin SQL functions are installed in this same project and reload the PostgREST schema cache. Your credentials are not the problem.`;
  }
  if(/no active ERP role|access role|not authorized|permission denied|not permitted/i.test(detail)){
    return `Your email and password were accepted, but ERP access is not enabled for this employee. An administrator must verify this account's active profile and role. ${detail}`;
  }
  return `Your email and password were accepted, but ${stage} did not finish loading: ${detail}. Your authenticated session was retained; refresh after fixing the ERP connection.`;
}
