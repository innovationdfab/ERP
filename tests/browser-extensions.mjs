// Isolated fixture for extension workflows, persistence, permissions and conflicts.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {todayISO} from '../src/erp-utils.js';
import {addDays,policyKey,followupKey} from '../src/erp-extensions.js';
const origin='https://dfab-extension-fixture.supabase.co';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5189','--strictPort'],{
 env:{...process.env,VITE_SUPABASE_URL:origin,VITE_SUPABASE_PUBLISHABLE_KEY:'fixture'},stdio:['ignore','pipe','inherit']});
let browser;
try{
 await Promise.race([once(server.stdout,'data'),once(server,'exit').then(()=>{throw new Error('Vite failed');})]);
 browser=await chromium.launch({headless:true,executablePath:process.env.ERP_CHROMIUM_PATH,args:JSON.parse(process.env.ERP_CHROMIUM_ARGS||'[]')});
 const page=await browser.newPage({viewport:{width:1440,height:950},reducedMotion:'reduce'});
 page.setDefaultTimeout(9000);
 const errors=[];page.on('pageerror',error=>errors.push(error.message));
 const date=addDays(todayISO(),-50),due=addDays(todayISO(),-40);
 const store=new Map([
  ['dfab-erp-products-v3',[['P1','Steel sheet','RAW MATERIAL','FABRICATION','KG','R01','ACTIVE']]],
  ['dfab-erp-vendors-v2',[['V1','Steel vendor','Bengaluru','','','','','','ACTIVE']]],
  ['dfab-erp-Opening Stock',[['OP1','P1','Stores','3','10','Posted']]],
  ['dfab-erp-sales-invoices-v2',[['1','SI-1',date,'Customer A','','','APPROVED','1000','NOT CONNECTED','']]],
  ['dfab-invoice-details-v1',{'SI-1':{form:{date,dueDate:due,currency:'INR',customer:'Customer A'}}}],
  ['dfab-erp-Customer Payments',[['R1','Customer A','SI-1',date,'200','Part Paid']]],
  ['dfab-erp-Credit Note',[['CN1','SI-1','Customer A',date,'100','Posted']]]
 ]);
 let conflict=false,restricted=false;
 await page.route(origin+'/**',async route=>{
  const endpoint=new URL(route.request().url()).pathname.split('/').at(-1),args=route.request().postDataJSON()||{};
  let response;
  if(endpoint==='token')response={access_token:'fixture',refresh_token:'fixture'};
  else if(endpoint==='user')response={id:'fixture',email:'qa@example.test',app_metadata:{}};
  else if(endpoint==='erp_admin_my_access')response=restricted?{enabled:true,is_admin:false,rights:{'Receivables Ageing':{view:true},'Sales Invoice':{view:true},'Customer Payments':{view:true}}}:{enabled:true,is_admin:true,rights:{}};
  else if(endpoint==='erp_admin_active_workflow')response=[];
  else if(endpoint==='erp_get_ui_state')response=[...store].map(([storage_key,payload])=>({storage_key,payload}));
  else if(endpoint==='erp_next_process_no')response=`${args.p_prefix}/${args.p_financial_year}/00001`;
  else if(endpoint==='erp_commit_process'){
   for(const key of Object.keys(args.p_changes))assert.deepEqual(args.p_expected[key],store.get(key)??null);
   for(const [key,value]of Object.entries(args.p_changes))store.set(key,value);response=true;
  }
  else if(endpoint==='erp_put_ui_state_if_unchanged'){
   if(conflict){conflict=false;await route.fulfill({status:409,json:{message:'Changed in another session. Reload and retry.'}});return;}
   assert.deepEqual(args.p_expected,store.get(args.p_storage_key)??null);
   store.set(args.p_storage_key,args.p_payload);response=true;
  }else throw new Error(`Unexpected ${endpoint}`);
  await route.fulfill({json:response});
 });
 await page.goto('http://127.0.0.1:5189');
 await page.getByTitle('Start welding',{exact:true}).click();
 await page.getByLabel('Email',{exact:true}).fill('qa@example.test');
 await page.getByLabel('Password',{exact:true}).fill('fixture-password');
 await page.getByRole('button',{name:'Login to ERP',exact:true}).click();
 await page.locator('.command-launcher').waitFor();
 const open=async title=>{
  await page.locator('.command-launcher').click();await page.locator('.command-input-row input').fill(title);
  await page.locator('.command-results button').filter({has:page.getByText(title,{exact:true})}).click();
  await page.getByRole('heading',{name:title,exact:true}).waitFor();
 };
 await open('Reorder Planning');
 await page.getByRole('button',{name:'Add reorder policy',exact:true}).click();
 const policy=page.getByRole('form',{name:'Reorder policy'});
 await policy.getByLabel('Product',{exact:true}).selectOption('P1');
 await policy.getByLabel('Preferred vendor',{exact:true}).selectOption('V1');
 await policy.getByLabel('Reorder point',{exact:true}).fill('5');
 await policy.getByLabel('Target stock',{exact:true}).fill('20');
 await policy.getByLabel('Lead time in days',{exact:true}).fill('2');
 await policy.getByRole('button',{name:'Save',exact:true}).click();
 await policy.waitFor({state:'hidden'});
 assert.equal(store.get(policyKey)[0].target,20);
 assert.equal(await page.getByRole('dialog').count(),0);
 await page.getByRole('button',{name:'Create indent',exact:true}).click();
 await page.getByRole('status').filter({hasText:'Draft purchase indent'}).waitFor();
 assert.equal(store.get('dfab-erp-Purchase Indents')[0][3],'17');
 assert.equal(Object.values(store.get('dfab-process-Purchase Indents'))[0].lines[0].quantity,'17');
 assert.equal(await page.getByRole('button',{name:'Create indent',exact:true}).isDisabled(),true);
 await page.reload();await page.locator('.command-launcher').waitFor();await open('Reorder Planning');
 assert.equal(await page.getByRole('button',{name:'Create indent',exact:true}).isDisabled(),true);
 console.log('Verified saved reorder policy, draft indent creation, duplicate prevention and reload');
 await open('Receivables Ageing');
 const aging=page.getByRole('row').filter({hasText:'SI-1'});
 assert.match(await aging.innerText(),/31–60 days.*1000|31–60 days.*1,000/);
 assert.match(await aging.innerText(),/700/);
 const download=page.waitForEvent('download');await page.getByRole('button',{name:'Export CSV',exact:true}).click();assert.match((await download).suggestedFilename(),/\.csv$/);
 await open('Collection Follow-ups');await page.getByRole('button',{name:'Add follow-up',exact:true}).click();
 const follow=page.getByRole('form',{name:'Collection follow-up'});
 await follow.getByLabel('Invoice',{exact:true}).selectOption('SI-1');await follow.getByLabel('Owner',{exact:true}).fill('Accounts');
 await follow.getByLabel('Note',{exact:true}).fill('Customer confirmed payment next week.');
 await follow.getByRole('button',{name:'Save',exact:true}).click();await follow.waitFor({state:'hidden'});
 assert.equal(store.get(followupKey)[0].invoice,'SI-1');
 await page.getByRole('button',{name:'Edit follow-up',exact:true}).click();
 await follow.getByLabel('Status',{exact:true}).selectOption('Done');
 await follow.getByRole('button',{name:'Save',exact:true}).click();await follow.waitFor({state:'hidden'});
 assert.equal(store.get(followupKey)[0].status,'Done');
 await open('Customer Statements');await page.getByLabel('Customer',{exact:true}).selectOption('Customer A');
 await page.getByLabel('Currency',{exact:true}).selectOption('INR');
 assert.match(await page.getByRole('row').filter({hasText:'SI-1'}).innerText(),/700/);
 await page.getByRole('button',{name:'Open invoice',exact:false}).click();
 await page.getByRole('heading',{name:'Sales Invoice',exact:true}).waitFor();
 await page.locator('.process-document-panel').waitFor();
 await page.locator('.page-subtitle').filter({hasText:'SI-1'}).waitFor();
 console.log('Verified ageing, credit allocation, CSV export, follow-up save/edit and linked statement invoice');
 for(const title of ['Reorder Planning','Receivables Ageing','Collection Follow-ups','Customer Statements']){
  await open(title);
  if(title==='Customer Statements')await page.getByLabel('Customer',{exact:true}).selectOption('Customer A');
  for(const width of [1440,1280,1024,768,390,320]){
   await page.setViewportSize({width,height:950});
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${title} at ${width}px`);
   const buttons=page.locator('.extension-table tbody button');
   assert.ok(await buttons.count(),`${title} needs populated action buttons`);
   const broken=await buttons.evaluateAll(elements=>elements.flatMap(button=>{
    const box=button.getBoundingClientRect();
    const textRects=[...button.childNodes].filter(node=>node.nodeType===Node.TEXT_NODE&&node.textContent.trim()).flatMap(node=>{
     const range=document.createRange();range.selectNodeContents(node);return [...range.getClientRects()];
    });
    return box.width<60||button.scrollHeight>button.clientHeight+1||button.scrollWidth>button.clientWidth+1
      ||textRects.some(rect=>rect.top<box.top-1||rect.bottom>box.bottom+1||rect.right>box.right+1)
      ?[{label:button.innerText,width:box.width,height:box.height}]:[];
   }));
   assert.deepEqual(broken,[],`${title} actions at ${width}px`);
   const scroll=page.locator('.extension-table');
   const bounds=await scroll.evaluate(element=>({height:element.clientHeight,limit:parseFloat(getComputedStyle(element).maxHeight),overflow:getComputedStyle(element).overflowY}));
   assert.ok(Number.isFinite(bounds.limit)&&bounds.height<=bounds.limit+1,`${title} has a bounded results area`);
   assert.equal(bounds.overflow,'auto');
   await scroll.evaluate(element=>{element.scrollLeft=element.scrollWidth;});
   const outside=await buttons.evaluateAll(elements=>elements.filter(button=>{
    const box=button.getBoundingClientRect();return box.left<0||box.right>innerWidth;
   }).map(button=>button.innerText));
   assert.deepEqual(outside,[],`${title} actions remain reachable at ${width}px`);
   if(process.env.ERP_EXTENSION_SCREENSHOTS&&title==='Receivables Ageing'&&[1440,390].includes(width)){
    await page.screenshot({path:`${process.env.ERP_EXTENSION_SCREENSHOTS}-${width}.png`,fullPage:true});
   }
  }
  await page.setViewportSize({width:1440,height:950});
 }
 console.log('Verified unbroken action labels, pinned actions and table scrolling on four screens at six viewport widths');
 await open('Reorder Planning');await page.getByRole('button',{name:'Edit policy',exact:true}).click();
 await policy.getByLabel('Target stock',{exact:true}).fill('30');conflict=true;
 await policy.getByRole('button',{name:'Save',exact:true}).click();await page.getByRole('alert').filter({hasText:'another session'}).waitFor();
 assert.equal(store.get(policyKey)[0].target,20);
 restricted=true;await page.reload();await page.locator('.command-launcher').waitFor();await open('Receivables Ageing');
 await page.getByRole('status').filter({hasText:'source modules'}).waitFor();
 assert.equal(await page.getByRole('table').count(),0);
 assert.deepEqual(errors,[]);
 console.log('Verified all extension mobile screens, failed-save handling and restricted-source permissions');
}finally{await browser?.close();server.kill();}
