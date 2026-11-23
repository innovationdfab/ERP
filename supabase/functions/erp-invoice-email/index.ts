import {createClient} from 'npm:@supabase/supabase-js@2.119.2';
import nodemailer from 'npm:nodemailer@10.6.1';
import {invoiceMailHtml} from '../../../src/invoice-mail.js';
const origins=(Deno.env.get('ERP_ALLOWED_ORIGINS')||'http://localhost:5173').split(',').map(s=>s.trim());
Deno.serve(async request=>{
 const origin=request.headers.get('Origin')||'';
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',...(origins.includes(origin)?{'Access-Control-Allow-Origin':origin}:{}),'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
 const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&!origins.includes(origin))return reply(403,{error:'Origin not allowed.'});
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='POST')return reply(405,{error:'POST required.'});
 const url=Deno.env.get('SUPABASE_URL')||'',anon=Deno.env.get('SUPABASE_ANON_KEY')||'',key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
 const jwt=request.headers.get('Authorization')||'';
 if(!jwt.startsWith('Bearer ')||!url||!anon)return reply(401,{error:'ERP sign-in required.'});
 const caller=createClient(url,anon,{global:{headers:{Authorization:jwt}},auth:{persistSession:false}});
 const {data:auth,error:authError}=await caller.auth.getUser();if(authError||!auth.user)return reply(401,{error:'Sign in again.'});
 const {data:allowed}=await caller.rpc('erp_admin_can_page',{p_page:'Sales Invoice',p_action:'export'});if(allowed!==true)return reply(403,{error:'Invoice export permission required.'});
 const host=Deno.env.get('ZOHO_SMTP_HOST')||'',user=Deno.env.get('ZOHO_SMTP_USER')||'',pass=Deno.env.get('ZOHO_SMTP_PASSWORD')||'',from=Deno.env.get('ZOHO_FROM_EMAIL')||user;
 const configured=!!host&&!!user&&!!pass&&!!key&&/^(smtp|smtppro)\.zoho\.(com|in|eu|com\.au|jp|ca|com\.cn)$/.test(host);
 let body;try{body=await request.json();}catch{return reply(400,{error:'Invalid request.'});}
 if(body.action==='status')return reply(200,{configured});
 if(!configured)return reply(503,{error:'Zoho SMTP is not configured.'});
 if(body.action!=='send'||typeof body.invoice!=='string'||typeof body.to!=='string'||!/^\S+@\S+\.\S+$/.test(body.to)||/[\r\n]/.test(body.to)||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.requestId))return reply(400,{error:'Invoice, recipient and request identifier required.'});
 const {data:job,error:startError}=await caller.rpc('erp_invoice_email_start',{p_invoice:body.invoice,p_to:body.to,p_request:body.requestId});
 if(startError)return reply(400,{error:startError.message});
 if(!job.created)return reply(200,{status:job.status});
 const elevated=createClient(url,key,{auth:{persistSession:false}});
 let status='unknown';
 try{
  const transport=nodemailer.createTransport({host,port:465,secure:true,auth:{user,pass},connectionTimeout:15000,socketTimeout:20000,tls:{minVersion:'TLSv1.2'},disableFileAccess:true,disableUrlAccess:true});
  const result=await transport.sendMail({from,to:body.to,subject:`DFAB Invoice ${job.invoice.number}`,html:invoiceMailHtml(job.invoice),attachments:[{filename:'invoice.html',content:invoiceMailHtml(job.invoice),contentType:'text/html'}],messageId:`<erp-${body.requestId}@${from.split('@')[1]}>`});
  status=result.accepted?.length?'sent':'failed';transport.close();
 }catch{status='unknown';}
 const {error:finishError}=await elevated.rpc('erp_invoice_email_finish',{p_request:body.requestId,p_org:job.organization_id,p_status:status});
 if(finishError)return reply(503,{error:'Email outcome could not be recorded. Check Zoho before resending.'});
 return reply(status==='sent'?200:502,{status,...(status==='sent'?{}:{error:'Zoho delivery outcome is unknown. Check sent mail before resending.'})});
});
