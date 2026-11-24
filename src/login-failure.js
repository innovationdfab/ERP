/** Clarify whether an error came from Supabase Auth or subsequent ERP initialization. */
export function loginFailureMessage(error,{credentialsVerified=false,stage='authentication'}={}) {
  const detail=String(error?.detail||error?.message||'Unknown error');
  const status=Number(error?.status)||0;
  const endpoint=String(error?.endpoint||'');
  const missingRpc=/PGRST202|could not find the function|schema cache|function .* does not exist/i.test(detail);
  if(!credentialsVerified){
    if(status===404)return `Supabase Authentication returned 404${endpoint?` at ${endpoint}`:''}. Check that VITE_SUPABASE_URL points to the same Supabase project as the employee account; restart the frontend after changing .env.`;
    return error?.message||'Unable to sign in. Verify your account email and password.';
  }
  if(missingRpc || (status===404 && stage!=='authentication')){
    const target=endpoint||'an ERP initialization request';
    const advice=target.startsWith('/functions/v1/')
      ? 'Verify that exact Edge Function is deployed to this Supabase project.'
      : 'Verify that exact ERP database function (RPC) is installed and accessible, then reload the PostgREST schema cache.';
    return `Your email and password were accepted by Supabase, but ${stage} returned ${status||'a missing-function error'} at ${target}. ${advice} Do not recreate this employee or reset the password before checking the failing endpoint.`;
  }
  if(/no active ERP role|access role|not authorized|permission denied|not permitted/i.test(detail)){
    return `Your email and password were accepted, but ERP access is not enabled for this employee. An administrator must verify this account's active profile and role. ${detail}`;
  }
  return `Your email and password were accepted, but ${stage} did not finish loading: ${detail}. Your authenticated session was retained; refresh after fixing the ERP connection.`;
}
