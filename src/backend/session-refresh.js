/** Refresh one browser session while preserving its identity and rotated refresh token. */
export function createSessionRefresh({read,write,remove,refresh,notify,lock=task=>task(),now=()=>Date.now()}){
  let pending=null;
  let currentToken='';
  const aliases=new Set();
  const claims=token=>{
    try{return JSON.parse(atob(token.split('.')[1].replaceAll('-','+').replaceAll('_','/')));}catch{return {};}
  };
  const sameSession=(first,second)=>{
    const a=claims(first),b=claims(second);
    return !!a.session_id&&a.session_id===b.session_id&&a.sub===b.sub&&a.iss===b.iss;
  };
  const recognize=saved=>{
    if(currentToken&&saved?.access_token!==currentToken&&!sameSession(currentToken,saved?.access_token))aliases.clear();
    currentToken=saved?.access_token||'';
  };
  const expiry=saved=>Number(saved.expires_at)||Number(claims(saved.access_token).exp)||0;
  const owned=(token,saved)=>token===saved?.access_token||aliases.has(token)||sameSession(token,saved?.access_token);
  const expired=error=>[400,401].includes(error.status)&&/refresh|invalid_grant|session.*(?:missing|not found|expired)|invalid.*token/i.test(error.message+' '+(error.code||''));
  const expire=saved=>{
    if(read()?.access_token!==saved.access_token)return;
    remove();aliases.clear();currentToken='';notify();
  };
  const ensure=async(token,{force=false}={})=>{
    const saved=read();recognize(saved);
    if(!saved||!owned(token,saved))return token;
    const expires=expiry(saved);
    if(force&&token!==saved.access_token&&(!expires||expires*1000>now()))return saved.access_token;
    if(!force&&(!expires||expires*1000-now()>60000))return saved.access_token;
    if(!saved.refresh_token){if(force||expires&&expires*1000<=now()){expire(saved);throw new Error('Your login session ended. Sign in again.');}return saved.access_token;}
    if(pending)return pending;
    pending=lock(async()=>{
      const latest=read();
      if(!latest||!owned(token,latest))throw new Error('The login session changed. Sign in again.');
      // Another tab or request may have renewed the token while this call waited.
      if(latest.access_token!==saved.access_token)return latest.access_token;
      if(!force&&expiry(latest)*1000-now()>60000)return latest.access_token;
      let renewed;
      try{renewed=await refresh(latest.refresh_token);}
      catch(error){if(expired(error))expire(latest);throw error;}
      if(!renewed?.access_token||!renewed?.refresh_token)throw new Error('Supabase did not return a complete refreshed session. Try again.');
      if(read()?.access_token!==latest.access_token)throw new Error('The login session changed while it was being renewed.');
      const next={...latest,access_token:renewed.access_token,refresh_token:renewed.refresh_token,
        expires_at:renewed.expires_at||(renewed.expires_in?Math.floor(now()/1000)+renewed.expires_in:null)};
      write(next);
      aliases.add(latest.access_token);aliases.add(next.access_token);currentToken=next.access_token;
      return next.access_token;
    });
    try{return await pending;}finally{pending=null;}
  };
  return {ensure};
}
