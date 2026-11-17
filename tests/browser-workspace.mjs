// Browser audit on isolated fixture data. Never sends traffic to production Supabase.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {readFileSync} from 'node:fs';
import {chromium} from 'playwright';
import {imantraReportDefinitions,imantraTransactions} from '../src/imantra-integration.js';

const port=5187;
const origin='https://dfab-workspace-fixture.supabase.co';
const routes=[...new Set([
  'Home','Admin Control','PO Number Details','SO Number Details','RM Inward and Outward','Route Card Monitoring','Customer Payment Overdue',...JSON.parse(readFileSync(new URL('./browser-routes.json',import.meta.url))),
  ...Object.keys(imantraReportDefinitions),...Object.keys(imantraTransactions)
])];
const catalog=JSON.parse(readFileSync(new URL('../src/admin-catalog.json',import.meta.url)));
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port',String(port),'--strictPort'],{
  env:{...process.env,VITE_SUPABASE_URL:origin,VITE_SUPABASE_PUBLISHABLE_KEY:'isolated-fixture'},
  stdio:['ignore','pipe','inherit']
});
let browser;
try {
  await Promise.race([once(server.stdout,'data'),once(server,'exit').then(()=>{throw new Error('Vite failed to start');})]);
  browser=await chromium.launch({headless:true,...(process.env.ERP_CHROMIUM_PATH?{
    executablePath:process.env.ERP_CHROMIUM_PATH,args:JSON.parse(process.env.ERP_CHROMIUM_ARGS||'[]')
  }:{})});
  const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
  page.setDefaultTimeout(5000);
  const errors=[],unexpected=[];
  page.on('pageerror',error=>errors.push(error.message));
  const storage=new Map([
    ['dfab-restored-preclean-data-v3-verified',true],
    ['dfab-erp-product-types',[['FINISHED GOOD']]],
    ['dfab-erp-uoms',[['NOS','Numbers']]],
    ['dfab-erp-products-v3',[['QA-P1','Fixture product','FINISHED GOOD','FABRICATION','NOS','R01','ACTIVE']]],
    ['dfab-erp-vendors-v2',[['QA-V1','Fixture vendor','Bengaluru','Karnataka','India','','','NOT REGISTERED','ACTIVE']]],
    ['dfab-erp-Purchase Indents',[['QA-INDENT','Stores','Fixture product','5','2026-11-17','Approval Pending']]],
    ['dfab-erp-product-groups-v2',[{name:'FABRICATION',description:'Fixture group',parent:''}]]
  ]);
  const dashboard={departments:[],teams:[],users:[],roles:[],catalog:catalog.map(row=>({...row,page:row.name,module_group:row.group})),
    events:[],templates:[],edges:[],storage:[],rights:[]};
  await page.route(origin+'/**',async route=>{
    const request=route.request();
    const endpoint=new URL(request.url()).pathname.split('/').at(-1);
    const args=request.postDataJSON()||{};
    let response;
    if(endpoint==='token') response={access_token:'fixture-admin',refresh_token:'fixture-refresh'};
    else if(endpoint==='user'&&request.method()==='PUT'){
      assert.deepEqual(args,{current_password:'fixture-password',password:'fixture-New123'});
      response={id:'fixture-admin',email:'qa@example.test'};
    }
    else if(endpoint==='user') response={id:'fixture-admin',email:'qa@example.test',app_metadata:{}};
    else if(endpoint==='erp_admin_my_access') response={enabled:true,is_admin:true,rights:{}};
    else if(endpoint==='erp_admin_dashboard') response=dashboard;
    else if(endpoint==='erp_admin_active_workflow') response=[];
    else if(endpoint==='erp_workspace_transactions') response=[];
    else if(endpoint==='erp_workspace_activity') response=[{occurred_at:'2026-11-17T00:00:00Z',actor:'QA',operation:'INSERT',reference:'fixture-log',module:'Products'}];
    else if(endpoint==='erp_get_ui_state') response=[...storage].map(([storage_key,payload])=>({storage_key,payload}));
    else if(endpoint==='erp_put_ui_state_if_unchanged'){
      assert.deepEqual(args.p_expected,storage.get(args.p_storage_key)??null);
      storage.set(args.p_storage_key,args.p_payload);
      response=true;
    }else if(['erp_commit_ui_state_batch','erp_restore_ui_state'].includes(endpoint)){
      for(const change of args.p_changes)assert.deepEqual(change.expected,storage.get(change.key)??null);
      for(const change of args.p_changes)storage.set(change.key,change.payload);
      response=true;
    }else if(endpoint==='logout')response={};
    else{
      unexpected.push(endpoint);
      return route.fulfill({status:400,json:{message:'Unexpected fixture request'}});
    }
    await route.fulfill({json:response});
  });
  await page.goto(`http://127.0.0.1:${port}`);
  await page.getByTitle('Start welding',{exact:true}).click();
  await page.getByLabel('Email',{exact:true}).fill('qa@example.test');
  await page.getByLabel('Password',{exact:true}).fill('fixture-password');
  await page.getByRole('button',{name:'Login to ERP',exact:true}).click();
  await page.locator('.command-launcher').waitFor();
  const open=async name=>{
    const launcher=page.locator('.command-launcher');
    if(await launcher.isVisible())await launcher.click();
    else await page.keyboard.press('Control+k');
    await page.locator('.command-input-row input').fill(name);
    await page.locator('.command-results button').filter({
      has:page.locator('.command-text b').and(page.getByText(name,{exact:true}))
    }).click();
    await page.locator('.page-transition-shell main h1').first().waitFor();
  };
  await page.locator('.command-launcher').click();
  await page.locator('.command-input-row input').fill('');
  const visibleRoutes=await page.locator('.command-text b').allTextContents();
  assert.deepEqual(visibleRoutes.filter(name=>!routes.includes(name)),[],'Every workspace menu page must be covered by the browser audit.');
  await page.keyboard.press('Escape');
  let reports=0;
  const failures=[];
  for(const route of (process.env.ERP_WORKSPACE_QUICK?['Home','Admin Control','Products','Customers','Vendors','Production BOM','Route Card','Settings','Change Password','Database Backup','Pending Approvals','Activity Log']:routes)){
    try{
      await open(route);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
      const generate=page.getByRole('button',{name:'Generate Report',exact:true});
      if(await generate.count()){
        await generate.click();
        await page.locator('[data-generated-report][aria-busy=false] table').waitFor();
        reports++;
      }
      if(errors.length)throw new Error(errors.splice(0).join('; '));
      console.log('PASS',route);
    }catch(error){
      failures.push({route,error:error.message.split('\n').slice(0,3).join(' ')});
      console.log('FAIL',failures.at(-1));
      await page.keyboard.press('Escape');
    }
  }
  assert.deepEqual(failures,[]);
  assert.deepEqual(unexpected,[]);
  await open('Pending Approvals');
  await page.getByRole('button',{name:'QA-INDENT',exact:true}).click();
  await page.getByRole('button',{name:'QA-INDENT',exact:true}).waitFor();
  await open('Activity Log');
  await page.getByText('fixture-log',{exact:true}).waitFor();
  await open('Settings');
  await page.getByLabel('Company display name').fill('QA Workspace');
  await page.getByRole('button',{name:'Save preferences',exact:true}).click();
  await page.getByText('Workspace preferences saved.',{exact:true}).waitFor();
  assert.equal(storage.get('dfab-workspace-settings').company,'QA Workspace');
  await open('Change Password');
  await page.getByLabel('Current password',{exact:true}).fill('fixture-password');
  await page.getByLabel('New password',{exact:true}).fill('fixture-New123');
  await page.getByLabel('Confirm new password',{exact:true}).fill('fixture-New123');
  await page.getByRole('button',{name:'Change password',exact:true}).click();
  await page.getByText('Password changed successfully.',{exact:true}).waitFor();
  await open('Vendor Price List');
  await page.getByRole('button',{name:'QA-P1 Fixture product'}).click();
  await page.getByRole('button',{name:'Add Price',exact:true}).click();
  await page.getByLabel('Vendor',{exact:true}).selectOption('QA-V1');
  await page.getByLabel('Rate',{exact:true}).fill('42');
  await page.getByRole('button',{name:'Save Price',exact:true}).click();
  await page.getByRole('cell',{name:'42',exact:true}).waitFor();
  await page.getByRole('button',{name:'Vendor Wise',exact:true}).click();
  await page.getByRole('button',{name:'QA-V1 Fixture vendor'}).click();
  await page.getByRole('cell',{name:'42',exact:true}).waitFor();
  await open('Vendor Price List Report');
  await page.getByRole('button',{name:'Generate Report',exact:true}).click();
  await page.getByRole('cell',{name:'42',exact:true}).waitFor();
  await open('Products');
  await page.getByRole('button',{name:'Create new',exact:true}).click();
  await page.getByLabel('Product description',{exact:true}).fill('Audit master product');
  const productForm=page.locator('.erp-form-grid');
  const selectField=(label)=>productForm.locator('label').filter({hasText:label}).locator('select');
  await selectField('Product type').selectOption('FINISHED GOOD');
  await selectField('Product group').selectOption('FABRICATION');
  await selectField('Stock UOM').selectOption('NOS');
  await page.getByRole('button',{name:'Save as Draft',exact:true}).click();
  await page.getByRole('cell',{name:'Audit master product',exact:true}).waitFor();
  const product=storage.get('dfab-erp-products-v3').find(row=>row[1]==='Audit master product');
  assert.equal(storage.get('dfab-erp-products-details-v1')[product[0]].description,'Audit master product');
  await open('WorkCenter/Machine Master');
  await page.getByRole('button',{name:'Add New WorkCenter',exact:true}).click();
  await page.getByLabel('* Workcenter Name',{exact:true}).fill('Fixture center');
  await page.getByLabel('Workcenter Location',{exact:true}).fill('Old bay');
  await page.getByRole('button',{name:'Save WorkCenter',exact:true}).click();
  const centerRow=page.getByRole('row').filter({hasText:'Fixture center'});
  await centerRow.locator('.row-actions button').first().click();
  await page.getByLabel('Workcenter Location',{exact:true}).fill('New bay');
  await page.getByRole('button',{name:'Save WorkCenter',exact:true}).click();
  await page.getByRole('cell',{name:'New bay',exact:true}).waitFor();
  assert.equal(storage.get('dfab-live-workcenters').length,1);
  await open('Production BOM');
  await page.getByRole('button',{name:'Create new BOM'}).click();
  await page.getByLabel('BOM Product*',{exact:true}).fill('Fixture product');
  const bomNumber=await page.getByLabel('BOM Number*',{exact:true}).inputValue();
  await page.locator('.editable-lines input').nth(0).fill('QA-P1');
  await page.locator('.editable-lines input').nth(2).fill('5');
  await page.getByRole('button',{name:'Save as Draft'}).click();
  await page.getByRole('button',{name:bomNumber,exact:true}).click();
  assert.equal(await page.locator('.editable-lines input').nth(2).inputValue(),'5');
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  await open('Route Card');
  await page.getByRole('button',{name:'Create new Route Card'}).click();
  await page.getByLabel('Route Card Product*',{exact:true}).fill('Fixture product');
  const routeNumber=await page.getByLabel('Route Card Number*',{exact:true}).inputValue();
  await page.locator('.editable-lines input').nth(0).fill('Laser cutting');
  await page.getByRole('button',{name:'Save as Draft'}).click();
  await page.getByRole('button',{name:routeNumber,exact:true}).click();
  assert.equal(await page.locator('.editable-lines input').nth(0).inputValue(),'Laser cutting');
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  await open('Database Backup');
  const downloaded=page.waitForEvent('download');
  await page.getByRole('button',{name:'Generate Backup',exact:true}).click();
  assert.match((await downloaded).suggestedFilename(),/^dfab-supabase-backup-.*\.json$/);
  await page.getByLabel('Restore backup JSON',{exact:true}).setInputFiles({
    name:'fixture.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({records:{'dfab-workspace-settings':{company:'Restored',currency:'INR',financialYear:'2026-2027'}}}))
  });
  await page.getByRole('alertdialog').getByRole('button',{name:'Confirm',exact:true}).click();
  await page.getByText('1 data sections saved to Supabase successfully.',{exact:true}).waitFor();
  assert.deepEqual(storage.get('dfab-workspace-settings'),{company:'Restored',currency:'INR',financialYear:'2026-2027'});
  await page.reload();
  await page.locator('.command-launcher').waitFor();
  await open('Products');
  await page.locator('.stat-card').filter({has:page.locator('.stat-label').and(page.getByText('All Products',{exact:true}))}).click();
  await page.getByRole('cell',{name:'Audit master product',exact:true}).waitFor();
  await page.setViewportSize({width:390,height:844});
  for(const route of ['Home','Products','Settings','Vendor Price List','Sales Invoice','Pending Approvals']){
    await open(route);
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,route);
  }
  assert.deepEqual(unexpected,[]);
  assert.deepEqual(errors,[]);
  console.log('Verified settings, password change request, price views and report, approvals, activity, master batch save and reload.');
  console.log(`Opened ${process.env.ERP_WORKSPACE_QUICK?12:routes.length} desktop routes and generated ${reports} reports.`);
}finally{
  await browser?.close();
  server.kill();
}
