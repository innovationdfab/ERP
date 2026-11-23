// Expiry and recovery against an isolated Supabase fixture.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {chromium} from 'playwright';
const origin='https://dfab-session-fixture.supabase.co';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5196','--strictPort'],{
 env:{...process.env,VITE_SUPABASE_URL:origin,VITE_SUPABASE_PUBLISHABLE_KEY:'fixture'},stdio:['ignore','pipe','inherit']});
let browser;
try{
 await Promise.race([once(server.stdout,'data'),once(server,'exit').then(()=>{throw new Error('Vite exited');})]);
 browser=await chromium.launch({headless:true,executablePath:process.env.ERP_CHROMIUM_PATH,args:JSON.parse(process.env.ERP_CHROMIUM_ARGS||'[]')});
 const page=await browser.newPage({viewport:{width:1440,height:950},reducedMotion:'reduce'});page.setDefaultTimeout(8000);
 const errors=[];page.on('pageerror',error=>errors.push(error.message));
 let refreshes=0,expired=false,revoke=false,deny=false,activityCalls=0;
 const state=new Map();
 await page.route(origin+'/**',async route=>{
  const request=route.request(),url=new URL(request.url()),endpoint=url.pathname.split('/').at(-1);
  const args=request.postDataJSON()||{},token=request.headers().authorization;
  let body;
  if(endpoint==='token'&&url.searchParams.get('grant_type')==='password')body={access_token:'old-token',refresh_token:'old-refresh',expires_at:Math.floor(Date.now()/1000)+3600};
  else if(endpoint==='token'){
   refreshes++;assert.equal(args.refresh_token,refreshes===1?'old-refresh':'new-refresh');
   if(revoke){await route.fulfill({status:400,json:{message:'Invalid Refresh Token: not found',code:'refresh_token_not_found'}});return;}
   body={access_token:'new-token',refresh_token:'new-refresh',expires_in:3600};
  }else if(endpoint==='user')body={id:'fixture',email:'qa@example.test',app_metadata:{}};
  else if(endpoint==='erp_admin_my_access')body={enabled:true,is_admin:false,rights:{'Activity Log':{view:true},Settings:{view:true,create:true,edit:true}}};
  else if(endpoint==='erp_admin_active_workflow')body=[];
  else if(endpoint==='erp_get_ui_state')body=[];
  else if(endpoint==='erp_workspace_activity'){
   activityCalls++;
   if(deny){await route.fulfill({status:403,json:{message:'Permission denied by source module'}});return;}
   if(expired&&token!=='Bearer new-token'||revoke){await route.fulfill({status:401,json:{message:'JWT expired',code:'PGRST301'}});return;}
   body=[{occurred_at:new Date().toISOString(),actor:'QA',operation:'Updated',reference:'Recovered activity',module:'Settings'}];
  }else if(endpoint==='erp_put_ui_state_if_unchanged'){
   assert.equal(token,'Bearer new-token');assert.deepEqual(args.p_expected,state.get(args.p_storage_key)??null);
   state.set(args.p_storage_key,args.p_payload);body=true;
  }else throw new Error(`Unexpected ${endpoint}`);
  await route.fulfill({json:body});
 });
 await page.goto('http://127.0.0.1:5196');await page.getByTitle('Start welding',{exact:true}).click();
 await page.getByLabel('Email',{exact:true}).fill('qa@example.test');await page.getByLabel('Password',{exact:true}).fill('fixture-password');
 await page.getByRole('button',{name:'Login to ERP',exact:true}).click();await page.locator('.command-launcher').waitFor();
 const open=async title=>{
  await page.locator('.command-launcher').click();await page.locator('.command-input-row input').fill(title);
  await page.locator('.command-results button').filter({has:page.getByText(title,{exact:true})}).click();
 };
 expired=true;
 await open('Activity Log');await page.getByText('Recovered activity',{exact:true}).waitFor();
 assert.equal(refreshes,1);assert.equal(activityCalls,2);
 const saved=await page.evaluate(()=>JSON.parse(localStorage.getItem('dfab-erp-supabase-session')));
 assert.equal(saved.refresh_token,'new-refresh');assert.ok(saved.expires_at>Date.now()/1000);
 await open('Settings');await page.getByLabel('Company display name').fill('Renewed session company');
 await page.getByRole('button',{name:'Save preferences',exact:true}).click();await page.getByText('Workspace preferences saved.',{exact:true}).waitFor();
 assert.equal(state.get('dfab-workspace-settings').company,'Renewed session company');
 deny=true;await open('Activity Log');
 await page.getByRole('alert').filter({hasText:'Permission denied'}).waitFor();
 assert.equal(refreshes,1);assert.ok(await page.locator('.command-launcher').count());
 deny=false;await open('Settings');
 revoke=true;
 await open('Activity Log');await page.getByRole('button',{name:'Login to ERP',exact:true}).waitFor();
 await page.getByRole('alert').filter({hasText:'session ended'}).waitFor();
 assert.equal(await page.evaluate(()=>localStorage.getItem('dfab-erp-supabase-session')),null);
 assert.equal(refreshes,2);assert.deepEqual(errors,[]);
 console.log('Verified 401 activity recovery, a single token refresh, rotated token persistence, subsequent save and revoked-session return to login');
}finally{await browser?.close();server.kill();}
