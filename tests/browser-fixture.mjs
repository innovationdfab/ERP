import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {chromium} from 'playwright';
import catalog from '../src/admin-catalog.json' with {type:'json'};

/** Isolated authenticated fixture. Every outbound request is intercepted. */
export async function launchFixture(port){
 const origin='https://dfab-local-fixture.supabase.co';
 const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port',String(port),'--strictPort'],{
  env:{...process.env,VITE_SUPABASE_URL:origin,VITE_SUPABASE_PUBLISHABLE_KEY:'local-fixture'},stdio:['ignore','pipe','inherit']});
 await Promise.race([once(server.stdout,'data'),once(server,'exit').then(()=>{throw new Error('Vite exited');})]);
 let browser;
 try{
  browser=await chromium.launch({headless:true,executablePath:process.env.ERP_CHROMIUM_PATH,args:JSON.parse(process.env.ERP_CHROMIUM_ARGS||'[]')});
  const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
  page.setDefaultTimeout(7000);
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  const store=new Map([
   ['dfab-restored-preclean-data-v3-verified',true],
   ['dfab-erp-product-types',[['FINISHED GOOD']]],['dfab-erp-uoms',[['NOS','Numbers']]],
   ['dfab-erp-product-groups-v2',[{name:'FABRICATION',description:'Fixture group',parent:''}]],
   ['dfab-erp-products-v3',[['QA-P1','Fixture product','FINISHED GOOD','FABRICATION','NOS','R01','ACTIVE']]],
   ['dfab-erp-vendors-v2',[['QA-V1','Fixture vendor','Bengaluru','Karnataka','India','','','NOT REGISTERED','ACTIVE']]]
  ]);
  const dashboard={departments:[],teams:[],users:[],roles:[],catalog:catalog.map(row=>({...row,page:row.name,module_group:row.group})),events:[],templates:[],edges:[],storage:[],rights:[]};
  await page.route('**/*',async route=>{
   const request=route.request(),url=new URL(request.url());
   if(url.hostname==='127.0.0.1'||url.hostname==='localhost'){await route.continue();return;}
   if(!request.url().startsWith(origin)){await route.fulfill({status:204,body:''});return;}
   const endpoint=url.pathname.split('/').at(-1),args=request.postDataJSON()||{};
   let response;
   if(endpoint==='token')response={access_token:'fixture',refresh_token:'fixture-refresh'};
   else if(endpoint==='user')response={id:'fixture',email:'qa@example.test',app_metadata:{}};
   else if(endpoint==='erp_admin_my_access')response={enabled:true,is_admin:true,rights:{}};
   else if(endpoint==='erp_admin_active_workflow'||endpoint==='erp_workspace_activity'||endpoint==='erp_workspace_transactions')response=[];
   else if(endpoint==='erp_admin_dashboard')response=dashboard;
   else if(endpoint==='erp_get_ui_state')response=[...store].map(([storage_key,payload])=>({storage_key,payload}));
   else if(endpoint==='erp_put_ui_state_if_unchanged'){
    assert.deepEqual(args.p_expected,store.get(args.p_storage_key)??null);
    store.set(args.p_storage_key,args.p_payload);response=true;
   }else if(endpoint==='erp_commit_ui_state_batch'){
    for(const change of args.p_changes)assert.deepEqual(change.expected,store.get(change.key)??null);
    for(const change of args.p_changes)store.set(change.key,change.payload);
    response=true;
   }else throw new Error(`Unexpected fixture request ${endpoint}`);
   await route.fulfill({json:response});
  });
  await page.goto(`http://127.0.0.1:${port}`);
  await page.getByTitle('Start welding',{exact:true}).click();
  await page.getByLabel('Email',{exact:true}).fill('qa@example.test');
  await page.getByLabel('Password',{exact:true}).fill('fixture-password');
  await page.getByRole('button',{name:'Login to ERP',exact:true}).click();
  await page.locator('.command-launcher').waitFor();
  const open=async name=>{
   await page.keyboard.press('Escape');await page.locator('.command-launcher').click();
   await page.locator('.command-input-row input').fill(name);
   await page.locator('.command-results button').filter({has:page.locator('.command-text b').and(page.getByText(name,{exact:true}))}).click();
   await page.locator('.command-backdrop').waitFor({state:'hidden'});
   await page.locator('main h1').first().waitFor();
  };
  return {browser,page,store,errors,open,close:async()=>{await browser.close();server.kill();}};
 }catch(error){await browser?.close();server.kill();throw error;}
}
