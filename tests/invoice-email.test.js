import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import ts from 'typescript';
import {invoiceMailHtml} from '../src/invoice-mail.js';
const original=readFileSync(new URL('../supabase/functions/erp-invoice-email/index.ts',import.meta.url),'utf8');let serial=0;
async function fixture({configured=true,allowed=true,smtpFail=false}={}){
 const sent=[],jobs=new Map();let handler;
 const env={ERP_ALLOWED_ORIGINS:'https://erp.example.test',SUPABASE_URL:'https://db.example.test',SUPABASE_ANON_KEY:'test-public',SUPABASE_SERVICE_ROLE_KEY:'test-service',ZOHO_SMTP_HOST:'smtppro.zoho.in',ZOHO_SMTP_USER:'billing@example.test',ZOHO_SMTP_PASSWORD:configured?'test-only-password':'',ZOHO_FROM_EMAIL:'billing@example.test'};
 const invoice={module:'Sales Invoice',number:'SI/1',date:'2026-11-23',party:'Test customer',lines:[{code:'P1',description:'Part',quantity:'2',rate:'100',cgst:9,sgst:9,igst:0}],total:236};
 globalThis.Deno={env:{get:key=>env[key]},serve:fn=>{handler=fn;}};
 globalThis.__mailDependencies={invoiceMailHtml,createClient:()=>({auth:{getUser:async()=>({data:{user:{id:'qa'}},error:null})},rpc:async(name,args)=>{
  if(name==='erp_admin_can_page')return {data:allowed};
  if(name==='erp_invoice_email_start'){const existing=jobs.get(args.p_request);if(existing)return {data:{created:false,status:existing.status}};jobs.set(args.p_request,{status:'processing'});return {data:{created:true,status:'processing',invoice,organization_id:'org'}};}
  if(name==='erp_invoice_email_finish'){jobs.get(args.p_request).status=args.p_status;return {error:null};}
  throw Error('Unexpected mail RPC');
 }}),nodemailer:{createTransport:options=>{assert.equal(options.secure,true);assert.equal(options.port,465);assert.equal(options.host,'smtppro.zoho.in');assert.equal(options.disableFileAccess,true);return {sendMail:async mail=>{sent.push(mail);if(smtpFail)throw Error('Simulated timeout');return {accepted:[mail.to]};},close(){}};}}};
 const source=original.replace(/import \{createClient\}[^;]+;/,'const createClient=globalThis.__mailDependencies.createClient;').replace(/import nodemailer[^;]+;/,'const nodemailer=globalThis.__mailDependencies.nodemailer;').replace(/import \{invoiceMailHtml\}[^;]+;/,'const invoiceMailHtml=globalThis.__mailDependencies.invoiceMailHtml;');
 const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.deepEqual(compiled.diagnostics,[]);
 await import('data:text/javascript;base64,'+Buffer.from(compiled.outputText+'\n// '+serial++).toString('base64'));
 const request=(body,origin='https://erp.example.test',token='Bearer qa-token')=>handler(new Request('https://db.example.test/functions/v1/erp-invoice-email',{method:'POST',headers:{Origin:origin,Authorization:token,'Content-Type':'application/json'},body:JSON.stringify(body)}));
 return {request,sent,jobs};
}
const send={action:'send',invoice:'SI/1',to:'customer@example.test',requestId:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'};
test('Zoho is unavailable until server credentials are configured',async()=>{const f=await fixture({configured:false});const status=await f.request({action:'status'});const body=await status.json();assert.equal(body.configured,false);assert.deepEqual(body.missingConfiguration,['ZOHO_SMTP_PASSWORD']);assert.doesNotMatch(JSON.stringify(body),/test-only-password|test-service/);assert.equal((await f.request(send)).status,503);assert.equal(f.sent.length,0);});
test('invoice email requires the approved origin, session and export right',async()=>{const f=await fixture({allowed:false});assert.equal((await f.request(send,'https://evil.example')).status,403);assert.equal((await f.request(send,undefined,'')).status,401);assert.equal((await f.request(send)).status,403);assert.equal(f.sent.length,0);});
test('Zoho uses TLS SMTP and does not duplicate an accepted request',async()=>{const f=await fixture();assert.equal((await f.request(send)).status,200);assert.equal(f.sent.length,1);assert.match(f.sent[0].html,/SI\/1/);assert.equal(f.sent[0].to,send.to);assert.equal(f.sent[0].from,'billing@example.test');assert.equal((await f.request(send)).status,200);assert.equal(f.sent.length,1);});
test('an uncertain SMTP result is retained and never automatically resent',async()=>{const f=await fixture({smtpFail:true});assert.equal((await f.request(send)).status,502);assert.equal(f.jobs.get(send.requestId).status,'unknown');await f.request(send);assert.equal(f.sent.length,1);});
test('recipient header injection and malformed request IDs are rejected',async()=>{const f=await fixture();assert.equal((await f.request({...send,to:'customer@example.test\r\nBcc:bad@example.test'})).status,400);assert.equal((await f.request({...send,requestId:'invalid'})).status,400);assert.equal(f.sent.length,0);});
