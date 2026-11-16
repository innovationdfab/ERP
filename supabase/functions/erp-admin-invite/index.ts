/** Deploy via: supabase functions deploy erp-admin-invite
 * The gateway and function both verify the caller JWT with auth.getUser()
 * and ERP ADMIN permissions are checked with the caller's identity before
 * any service-role operation. Service key never reaches the browser.
 */
import { createClient } from 'npm:@supabase/supabase-js@2';

const url = Deno.env.get('SUPABASE_URL') || '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const allowedOrigins = (Deno.env.get('ERP_ALLOWED_ORIGINS') || 'http://localhost:5173')
  .split(',').map(x => x.trim()).filter(Boolean);

Deno.serve(async request => {
  const origin = request.headers.get('Origin') || '';
  const allowed = !origin || allowedOrigins.includes(origin);
  const headers = {
    'Content-Type':'application/json',
    'Cache-Control':'no-store',
    'Vary':'Origin',
    ...(allowed && origin ? {'Access-Control-Allow-Origin':origin} : {}),
    'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods':'POST, OPTIONS',
  };
  const respond = (status:number, body:Record<string,unknown>) => new Response(JSON.stringify(body),{status,headers});
  if (!allowed) return respond(403,{error:'Origin not authorized for ERP administration.'});
  if (request.method === 'OPTIONS') return new Response(null,{status:204,headers});
  if (request.method !== 'POST') return respond(405,{error:'POST required.'});
  if (!url || !anonKey || !serviceKey) return respond(503,{error:'Admin invitation service is not configured.'});
  const bearer = request.headers.get('Authorization') || '';
  const jwt = /^Bearer (.+)$/i.exec(bearer)?.[1];
  if (!jwt) return respond(401,{error:'ERP login required.'});
  try {
    const caller = createClient(url,anonKey,{global:{headers:{Authorization:`Bearer ${jwt}`}},auth:{persistSession:false,autoRefreshToken:false}});
    const {data:{user},error:authError} = await caller.auth.getUser(jwt);
    if (authError || !user?.id) return respond(401,{error:'Expired or invalid ERP session.'});
    const {data:admin,error:adminError} = await caller.rpc('erp_admin_is_admin');
    if (adminError || admin !== true) return respond(403,{error:'Administrator authorization required.'});
    const body = await request.json();
    const email = String(body.email||'').trim().toLowerCase();
    const name = String(body.name||'').trim();
    const roleIds = Array.isArray(body.role_ids) ? body.role_ids : [];
    const deptId = body.department_id || null;
    const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if(!/^\S+@\S+\.\S+$/.test(email)||email.length>254||name.length<2||name.length>100||!roleIds.length||roleIds.length>20||!roleIds.every((r:unknown)=>typeof r==='string'&&uuid.test(r))||(deptId&&!uuid.test(deptId)))
      return respond(400,{error:'Valid email, name, department and role are required.'});
    const domains=(Deno.env.get('ERP_INVITE_EMAIL_DOMAINS')||'').split(',').map(v=>v.trim().toLowerCase()).filter(Boolean);
    if(domains.length&&!domains.includes(email.split('@')[1])) return respond(403,{error:'Email domain is not allowed for ERP accounts.'});
    // Validate role IDs and department against the caller's current organization.
    const {data:state,error:stateError}=await caller.rpc('erp_admin_dashboard');
    if(stateError||!state||roleIds.some((id:string)=>!state.roles.some((r:{id:string,active:boolean})=>r.id===id&&r.active))||(deptId&&!state.departments.some((d:{id:string,active:boolean})=>d.id===deptId&&d.active)))
      return respond(400,{error:'Selected role or department is not valid for this ERP organization.'});
    // Creating an Auth account with an invitation MUST happen server-side.
    const elevated = createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:invite,error:inviteError}=await elevated.auth.admin.inviteUserByEmail(email,{data:{full_name:name}});
    if(inviteError||!invite?.user?.id) return respond(400,{error:inviteError?.message||'Invitation could not be sent.'});
    // ERP profile is created by the existing auth.users trigger with zero roles.
    // Admin RPC atomically assigns the selected roles and department.
    const {error:assignError} = await caller.rpc('erp_admin_save_user',{
      p_user_id:invite.user.id,p_department_id:deptId,p_display_name:name,p_active:true,p_role_ids:roleIds,
    });
    if(assignError) return respond(500,{error:'Invitation sent, but ERP access could not be assigned. Open Users & logins and grant access to this invited employee. '+assignError.message});
    return respond(200,{invited:true,email,user_id:invite.user.id});
  } catch(err) {
    return respond(500,{error:err instanceof Error?err.message:'Unexpected invitation error.'});
  }
});
