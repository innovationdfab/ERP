// Run against an isolated in-memory Supabase fixture. No production data is used.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {chromium} from 'playwright';
import {referenceForms,referenceFetch} from '../src/reference-forms.js';
import {todayISO} from '../src/erp-utils.js';
import {stockMovementSources} from '../src/imantra-stock.js';

const port=5184;
const origin='https://dfab-forms-test.supabase.co';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port',String(port),'--strictPort'],{
  env:{...process.env,VITE_SUPABASE_URL:origin,VITE_SUPABASE_PUBLISHABLE_KEY:'local-fixture'},
  stdio:['ignore','pipe','inherit']
});
let browser;
try {
  await Promise.race([
    once(server.stdout,'data'),
    once(server,'exit').then(()=>{throw new Error('Vite exited before browser tests')})
  ]);
  browser=await chromium.launch({headless:true,...(process.env.ERP_CHROMIUM_PATH?{executablePath:process.env.ERP_CHROMIUM_PATH,args:JSON.parse(process.env.ERP_CHROMIUM_ARGS||'[]')}:{})});
  const page=await browser.newPage({viewport:{width:1440,height:900},reducedMotion:'reduce'});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  const store=new Map([
    ['dfab-erp-Purchase Orders',[['QA-PO','Supplier',todayISO(),'120','2026-12-01','Approved',{version:1,header:{Item:'Steel',Qty:'12'}}]]],
    ['dfab-erp-GRN',[['QA-GRN','QA-PO','Supplier','Steel','10','Awaiting QC',{version:1,header:{Date:todayISO()}}]]],
    ['dfab-erp-Sales Quotations',[['SQ-100','Fixture Customer','ENQ-100','1200','Accepted']]],
    ['dfab-erp-Sales Orders',[['SO-LEGACY','Existing Customer','PO-1','Existing Item','1','2026-11-22','Draft']]]
  ]);
  const rights=Object.fromEntries([...Object.keys(referenceForms),...stockMovementSources,'Customer Payments','Procurement Planning','Sales Register','Sales Register Headerwise','Pending Receivables','Stock Ledger'].map(title=>[title,{view:true,create:true,edit:true,approve:true,delete:true}]));
  await page.route(origin+'/**',async route=>{
    const request=route.request();
    const endpoint=new URL(request.url()).pathname.split('/').at(-1);
    const data=request.postDataJSON();
    let body;
    if(endpoint==='token') body={access_token:'fixture-access-token'};
    else if(endpoint==='user') body={id:'fixture-user',email:'qa@example.test',app_metadata:{}};
    else if(endpoint==='erp_admin_my_access') body={enabled:true,is_admin:false,rights};
    else if(endpoint==='erp_admin_active_workflow') body=[];
    else if(endpoint==='erp_get_ui_state') body=[...store].map(([storage_key,payload])=>({storage_key,payload}));
    else if(endpoint==='erp_put_ui_state_if_unchanged'){
      assert.deepEqual(data.p_expected,store.get(data.p_storage_key)??null);
      store.set(data.p_storage_key,data.p_payload);
      body=true;
    }else if(endpoint==='erp_commit_ui_state_batch'){
      for(const change of data.p_changes) assert.deepEqual(change.expected,store.get(change.key)??null);
      for(const change of data.p_changes) store.set(change.key,change.payload);
      body=true;
    }else throw new Error(`Unexpected fixture request ${endpoint}`);
    await route.fulfill({json:body});
  });
  page.setDefaultTimeout(7000);
  await page.goto(`http://127.0.0.1:${port}`);
  await page.getByTitle('Start welding',{exact:true}).click();
  await page.getByLabel('Email',{exact:true}).fill('qa@example.test');
  await page.getByLabel('Password',{exact:true}).fill('fixture-password');
  await page.getByRole('button',{name:'Login to ERP',exact:true}).click();
  await page.locator('.command-launcher').waitFor({state:'attached'});
  const open=async title=>{
    await page.keyboard.press('Control+k');
    await page.locator('.command-input-row input').fill(title);
    await page.locator('.command-results button').filter({has:page.locator('.command-text b').and(page.getByText(title,{exact:true}))}).click();
    await page.locator('main h1').and(page.getByText(title,{exact:true})).waitFor();
  };
  const generateReport=async title=>{
    await open(title);
    await page.getByRole('button',{name:'Generate Report',exact:true}).click();
    const table=page.locator('[data-generated-report] table');
    await table.waitFor();
    return table;
  };
  const editorPage=page.locator('.page-transition-shell > .transaction-editor-page');
  const openForm=async title=>{
    await open(title);
    if(title==='Sales Invoice') await page.getByRole('button',{name:'Create new',exact:true}).click();
    else await page.locator('.page-title-row .primary-pill').click();
    await editorPage.waitFor();
    assert.equal(await page.getByRole('dialog').count(),0,title);
    assert.equal(await page.locator('.modal-backdrop').count(),0,title);
    return editorPage;
  };
  const exit=async editor=>{
    await editor.getByRole('button',{name:'Cancel',exact:true}).click();
    await editor.waitFor({state:'hidden'});
  };
  for(const [title,capture] of (process.env.ERP_FORMS_QUICK?[]:Object.entries(referenceForms))){
    console.log(`Checking ${title}`);
    const editor=await openForm(title);
    const labels=await editor.locator('.erp-field-grid label > span,.invoice-form-grid label > span').allTextContents();
    if(title==='Sales Invoice'){
      await editor.getByRole('button',{name:'Additional details',exact:true}).click();
      labels.push(...await editor.locator('.invoice-form-grid label > span').allTextContents());
    }
    for(const label of ['Date','Series',capture.party,...capture.fields].filter(Boolean)){
      assert.ok(labels.includes(label),`${title} is missing ${label}`);
    }
    assert.equal(await editor.getByRole('button',{name:'Fetch',exact:true}).count(),referenceFetch[title]?1:0,title);
    if(capture.files.length){
      await editor.getByRole('button',{name:'Attachments',exact:true}).click();
      for(const label of capture.files) assert.ok(await editor.locator('input[type=file]').evaluateAll((inputs,target)=>inputs.some(input=>input.getAttribute('aria-label')===target),label),`${title} is missing ${label}`);
    }
    await exit(editor);
  }
  for(const title of ['Customer Payments','Procurement Planning']){
    const form=await openForm(title);
    assert.ok(await form.locator('.erp-field-grid input').count());
    await exit(form);
  }
  const desktop=await openForm('Sales Orders');
  assert.ok(await desktop.getByRole('heading',{name:'Document details',exact:true}).isVisible());
  assert.equal(await desktop.getByRole('button',{name:'Details',exact:true}).getAttribute('aria-current'),'true');
  const desktopLayout=await desktop.evaluate(element=>{
    const shell=element.parentElement.getBoundingClientRect();
    const toolbar=element.querySelector('.transaction-editor-actions').getBoundingClientRect();
    const body=element.querySelector('.transaction-editor-body').getBoundingClientRect();
    const section=element.querySelector('.erp-field-grid');
    const label=section.querySelector('label');
    return {columns:getComputedStyle(section).gridTemplateColumns.split(' ').length,
      labelColumns:getComputedStyle(label).gridTemplateColumns.split(' ').length,
      toolbarBottom:toolbar.bottom,bodyTop:body.top,shellBottom:shell.bottom};
  });
  assert.equal(desktopLayout.columns,4);
  assert.equal(desktopLayout.labelColumns,1);
  assert.ok(desktopLayout.toolbarBottom<=desktopLayout.bodyTop);
  assert.ok(desktopLayout.toolbarBottom<=desktopLayout.shellBottom);
  const spacing=await desktop.evaluate(element=>{
    const tools=element.querySelector('.transaction-editor-tools');
    const details=element.querySelector('.erp-field-grid');
    const controls=[...details.querySelectorAll('label > :is(input,select,textarea)')];
    const boxes=controls.slice(0,4).map(control=>control.getBoundingClientRect());
    return {toolbarHeight:tools.offsetHeight,firstRowTops:boxes.map(box=>box.top),fieldCount:controls.length};
  });
  assert.ok(spacing.toolbarHeight<58);
  if(process.env.ERP_FORM_SCREENSHOT)await page.screenshot({path:process.env.ERP_FORM_SCREENSHOT});
  assert.equal(new Set(spacing.firstRowTops).size,1,JSON.stringify(spacing));
  assert.equal(spacing.fieldCount,15);
  assert.equal(await desktop.locator('.erp-field-grid label > span').first().innerText(),'SO No');
  assert.equal(await desktop.getByRole('region',{name:'Connected source documents'}).count(),0);
  assert.match(await desktop.getByLabel('Workflow summary').innerText(),/Next step\s+Work Order/);
  await exit(desktop);
  console.log(process.env.ERP_FORMS_QUICK?'Checked targeted transaction forms':`Opened ${Object.keys(referenceForms).length} reference forms and two other transaction forms inline`);
  await page.setViewportSize({width:390,height:690});
  const editor=await openForm('Sales Orders');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  const mobileLayout=await editor.evaluate(element=>{
    const body=element.querySelector('.transaction-editor-body');
    const actions=element.querySelector('.transaction-editor-actions');
    const before=actions.getBoundingClientRect().top;
    body.scrollTop=body.scrollHeight;
    return {outerScroll:element.scrollTop,fieldScroll:body.scrollTop,
      fieldWidth:body.clientWidth,fieldContentWidth:body.scrollWidth,
      toolbarTop:actions.getBoundingClientRect().top,previousToolbarTop:before,
      toolbarBottom:actions.getBoundingClientRect().bottom,viewportHeight:innerHeight};
  });
  assert.equal(mobileLayout.outerScroll,0);
  assert.ok(mobileLayout.fieldScroll>0,JSON.stringify(mobileLayout));
  assert.ok(mobileLayout.fieldContentWidth<=mobileLayout.fieldWidth);
  assert.equal(mobileLayout.toolbarTop,mobileLayout.previousToolbarTop);
  assert.ok(mobileLayout.toolbarBottom<=mobileLayout.viewportHeight);
  await editor.getByRole('button',{name:'Back to records'}).click();
  await editor.waitFor({state:'hidden'});
  await page.getByRole('button',{name:'SO-LEGACY',exact:true}).waitFor();
  await page.locator('.page-title-row .primary-pill').click();
  await editor.waitFor();
  await editor.getByRole('button',{name:'Save',exact:true}).click();
  assert.match(await editor.getByRole('alert').innerText(),/required/);
  assert.equal(await page.getByRole('dialog').count(),0);
  const field=(label,scope=editor)=>scope.locator('label').filter({has:page.locator("span").and(page.getByText(label,{exact:true}))}).locator('input,textarea,select');
  await field('Customer').fill('Manually entered customer');
  await editor.getByRole('button',{name:'Fetch',exact:true}).click();
  await field('Find by number or party').fill('no match');
  await editor.getByText('No documents match the search.',{exact:true}).waitFor();
  await field('Find by number or party').fill('Fixture Customer');
  await field('Source document').selectOption('SQ-100');
  await editor.getByRole('button',{name:'Fetch document',exact:true}).click();
  assert.equal(await field('Customer').inputValue(),'Manually entered customer');
  assert.equal(await editor.getByRole('button',{name:'Fetch',exact:true}).getAttribute('aria-expanded'),'false');
  await field('SO No').fill('SO-QA-100');
  await field('PO Number').fill('QA-PO');
  await field('Product').fill('QA item');
  await field('Qty').fill('2');
  await field('Expected Delivery Date.').fill('2026-12-01');
  await field('Order Remarks').fill('Save and reopen this note');
  assert.equal(await field('Quotation No').inputValue(),'SQ-100');
  const sourceCard=editor.getByRole('region',{name:'Connected source documents'});
  assert.match(await sourceCard.innerText(),/Fixture Customer/);
  assert.match(await sourceCard.innerText(),/1200/);
  await editor.getByRole('button',{name:'Additional details',exact:true}).click();
  await field('A Number').fill('QA-A-100');
  await editor.getByRole('button',{name:'Attachments',exact:true}).click();
  const attachment=editor.locator('.transaction-attachment-card');
  assert.ok(await attachment.getByRole('heading',{name:'Order Copy'}).isVisible());
  assert.ok((await attachment.locator('.premium-dropzone').boundingBox()).height<105);
  await editor.locator('input[type=file]').setInputFiles({name:'order.txt',mimeType:'text/plain',buffer:Buffer.from('Fixture order copy')});
  await editor.getByRole('link',{name:'Download order.txt'}).waitFor();
  await editor.getByRole('button',{name:'Save',exact:true}).click();
  await page.getByRole('button',{name:'SO-QA-100',exact:true}).waitFor();
  await page.reload();
  await page.locator('.command-launcher').waitFor({state:'attached'});
  await open('Sales Orders');
  await page.getByRole('button',{name:'SO-LEGACY',exact:true}).waitFor();
  await page.getByRole('button',{name:'SO-QA-100',exact:true}).click();
  const edit=editorPage;
  await edit.waitFor();
  assert.equal(await field('Order Remarks',edit).inputValue(),'Save and reopen this note');
  assert.match(await edit.getByLabel('Workflow summary').innerText(),/Fetched from\s+Sales Quotations · SQ-100/);
  await edit.getByRole('button',{name:'Attachments',exact:true}).click();
  await edit.getByRole('link',{name:'Download order.txt'}).waitFor();
  await exit(edit);
  console.log('Verified Fetch, inline validation, existing records, attachment persistence and mobile Sales Order create/edit');
  const order=page.locator('tbody tr').filter({has:page.getByRole('button',{name:'SO-QA-100',exact:true})});
  await order.getByTitle('Create Work Order',{exact:true}).click();
  const gate=page.getByRole('alertdialog');
  await gate.waitFor();
  assert.match(await gate.innerText(),/Cannot create Work Order/);
  await gate.getByRole('button',{name:'OK',exact:true}).click();
  await order.getByTitle('Advance status',{exact:true}).click();
  await order.getByText('Approved',{exact:true}).waitFor();
  await order.getByTitle('Create Work Order',{exact:true}).click();
  await page.locator('main h1').and(page.getByText('Work Order',{exact:true})).waitFor();
  const [linked]=store.get('dfab-workflow-links-v1');
  assert.equal(linked.reference,'SO-QA-100');
  assert.equal(linked.to,'Work Order');
  assert.equal(store.get('dfab-erp-Work Order')[0][1],'SO-QA-100');
  console.log('Verified Sales Order status gate and linked Work Order handoff');
  const work=page.locator('tbody tr').filter({has:page.getByRole('button',{name:store.get('dfab-erp-Work Order')[0][0],exact:true})});
  await work.getByTitle('Advance status',{exact:true}).click();
  await page.getByRole('alertdialog').getByText('Machine is required.',{exact:true}).waitFor();
  await page.getByRole('alertdialog').getByRole('button',{name:'OK',exact:true}).click();
  await work.getByTitle('Edit',{exact:true}).click();
  await field('Machine',editorPage).fill('Machine A');
  await editorPage.getByRole('button',{name:'Save',exact:true}).click();
  await work.getByTitle('Advance status',{exact:true}).click();
  await work.getByText('Released',{exact:true}).waitFor();
  await work.getByTitle('Create Material Request',{exact:true}).click();
  await page.getByRole('heading',{name:'Material Request',exact:true}).waitFor();
  const request=store.get('dfab-erp-Material Request')[0];
  assert.equal(request[1],store.get('dfab-erp-Work Order')[0][0]);
  assert.equal(request[2],'');
  assert.equal(request[3],'');
  console.log('Verified production release requires a machine and material requests preserve the work-order link');

  await open('GRN');
  const grn=page.locator('tbody tr').filter({has:page.getByRole('button',{name:'QA-GRN',exact:true})});
  await grn.getByTitle('Advance status',{exact:true}).click();
  await page.getByRole('alertdialog').getByText('Pass Inward QC before accepting this GRN into stock.').waitFor();
  await page.getByRole('alertdialog').getByRole('button',{name:'OK',exact:true}).click();
  await grn.getByTitle('Create Inward QC',{exact:true}).click();
  await page.getByRole('heading',{name:'Inward QC',exact:true}).waitFor();
  const inspection=page.locator('tbody tr').filter({has:page.getByRole('button',{name:store.get('dfab-erp-Inward QC')[0][0],exact:true})});
  await inspection.getByTitle('Edit',{exact:true}).click();
  await field('Inspector',editorPage).fill('Inspector A');
  await editorPage.getByRole('button',{name:'Save',exact:true}).click();
  await inspection.getByTitle('Advance status',{exact:true}).click();
  await inspection.getByText('Passed',{exact:true}).waitFor();
  assert.equal(await inspection.getByTitle('Advance status',{exact:true}).isEnabled(),false);
  await open('GRN');
  await grn.getByTitle('Advance status',{exact:true}).click();
  await grn.getByText('Accepted',{exact:true}).waitFor();
  console.log('Verified GRN stock acceptance follows a passed inward inspection');
  const stock=await generateReport('Stock Ledger');
  const movement=stock.getByRole('row').filter({hasText:'QA-GRN'});
  assert.deepEqual(await movement.getByRole('cell').allTextContents(),['1',todayISO(),'GRN','QA-GRN','Steel','-','10','0','10','-']);
  const receiptForm=await openForm('GRN');
  await receiptForm.getByRole('button',{name:'Fetch',exact:true}).click();
  await field('Source document',receiptForm).selectOption('QA-PO');
  await receiptForm.getByRole('button',{name:'Fetch document',exact:true}).click();
  assert.equal(await field('PO Ref No',receiptForm).inputValue(),'QA-PO');
  assert.equal(await field('Vendor',receiptForm).inputValue(),'Supplier');
  assert.equal(await field('Received Qty',receiptForm).inputValue(),'');
  await exit(receiptForm);
  console.log('Verified receipt Fetch leaves actual received quantity for staff confirmation');
  const purchase=await openForm('Purchase');
  await field('PO No',purchase).fill('Unrelated PO');
  await purchase.getByRole('button',{name:'Fetch',exact:true}).click();
  await field('Source document',purchase).selectOption('QA-GRN');
  await purchase.getByRole('button',{name:'Fetch document',exact:true}).click();
  assert.match(await purchase.getByRole('alert').innerText(),/Clear PO No/);
  await field('PO No',purchase).clear();
  await purchase.getByRole('button',{name:'Fetch document',exact:true}).click();
  assert.equal(await field('PO No',purchase).inputValue(),'QA-PO');
  assert.equal(await field('Vendor',purchase).inputValue(),'Supplier');
  await exit(purchase);
  const invoice=await openForm('Sales Invoice');
  await field('Customer',invoice).fill('Invoice customer');
  await invoice.getByRole('button',{name:'Additional details',exact:true}).click();
  await field('IRN No',invoice).fill('QA-IRN-123');
  await invoice.getByRole('button',{name:'Products',exact:true}).click();
  await invoice.locator('tbody input').nth(1).fill('Invoice item');
  await invoice.locator('tbody input').nth(3).fill('100');
  await invoice.getByLabel('Line 1 UOM',{exact:true}).fill('NOS');
  await invoice.getByRole('button',{name:'Charges',exact:true}).click();
  await invoice.getByLabel('Freight Charges amount',{exact:true}).fill('7');
  await invoice.getByRole('button',{name:'External Expenses',exact:true}).click();
  await invoice.getByLabel('MPT Charges',{exact:true}).fill('4');
  const summary=invoice.getByLabel('Invoice summary');
  assert.match(await summary.innerText(),/Taxable amount\s+100\.00/);
  assert.match(await summary.innerText(),/Tax\s+18\.00/);
  assert.match(await summary.innerText(),/Total\s+125\.00/);
  await invoice.getByRole('button',{name:'Details',exact:true}).click();
  assert.match(await summary.innerText(),/125\.00/);
  await invoice.getByRole('button',{name:'Save as Draft',exact:true}).click();
  await page.locator('.sales-table-wrap .link-button').first().click();
  await page.getByRole('button',{name:'Edit invoice',exact:true}).click();
  await invoice.getByRole('button',{name:'Additional details',exact:true}).click();
  assert.equal(await field('IRN No',invoice).inputValue(),'QA-IRN-123');
  await invoice.getByRole('button',{name:'Charges',exact:true}).click();
  assert.equal(await invoice.getByLabel('Freight Charges amount',{exact:true}).inputValue(),'7');
  await invoice.getByRole('button',{name:'External Expenses',exact:true}).click();
  assert.equal(await invoice.getByLabel('MPT Charges',{exact:true}).inputValue(),'4');
  await invoice.getByRole('button',{name:'Products',exact:true}).click();
  const table=invoice.getByRole('region',{name:'Products fields'}).locator('.table-wrap');
  assert.ok(await table.evaluate(element=>element.scrollWidth>element.clientWidth));
  assert.ok(await invoice.evaluate(element=>{
    const body=element.querySelector('.transaction-editor-body');
    return body.scrollWidth===body.clientWidth;
  }));
  await invoice.getByRole('button',{name:'Submit for Approval',exact:true}).click();
  await invoice.waitFor({state:'hidden'});
  await page.locator('.sales-table-wrap .link-button').first().click();
  const dialog=page.getByRole('dialog');
  await dialog.getByRole('button',{name:'Approve invoice',exact:true}).click();
  await dialog.getByText('APPROVED',{exact:true}).waitFor();
  assert.equal(store.get('dfab-erp-sales-invoices-v2')[0][6],'APPROVED');
  assert.equal(await dialog.getByRole('button',{name:'Edit invoice',exact:true}).isEnabled(),false);
  await dialog.getByRole('button',{name:'Close',exact:true}).click();
  const invoiceNumber=store.get('dfab-erp-sales-invoices-v2')[0][1];
  const sales=await generateReport('Sales Register');
  const sale=sales.getByRole('row').filter({hasText:invoiceNumber});
  assert.match((await sale.getByRole('cell').allTextContents()).join('|'),/Invoice item\|1\|NOS\|100\|18\|118/);
  const header=await generateReport('Sales Register Headerwise');
  assert.match(await header.getByRole('row').filter({hasText:invoiceNumber}).innerText(),/125/);
  const pending=await generateReport('Pending Receivables');
  assert.match(await pending.getByRole('row').filter({hasText:invoiceNumber}).innerText(),/125/);
  const payment=await openForm('Customer Payments');
  await payment.getByRole('button',{name:'Fetch',exact:true}).click();
  await field('Source document',payment).selectOption(invoiceNumber);
  await payment.getByRole('button',{name:'Fetch document',exact:true}).click();
  assert.equal(await field('Amount',payment).inputValue(),'');
  assert.equal(await field('Customer',payment).inputValue(),'Invoice customer');
  await field('Receipt No',payment).fill('QA-RECEIPT-1');
  await field('Amount',payment).fill('125');
  await payment.getByRole('button',{name:'Save',exact:true}).click();
  const receipt=page.locator('tbody tr').filter({has:page.getByRole('button',{name:'QA-RECEIPT-1',exact:true})});
  await receipt.getByTitle('Advance status',{exact:true}).click();
  await receipt.getByText('Settled',{exact:true}).waitFor();
  assert.equal(store.get('dfab-erp-Customer Payments')[0][2],invoiceNumber);
  const settled=await generateReport('Pending Receivables');
  assert.equal(await settled.getByRole('row').filter({hasText:invoiceNumber}).count(),0);
  console.log('Verified invoice register lines and totals, posted stock ledger and receivable removal after settlement');
  rights['Customer Payments'].view=false;
  await page.reload();
  await page.locator('.command-launcher').waitFor({state:'attached'});
  await open('Pending Receivables');
  assert.ok(await page.getByRole('button',{name:'Generate Report',exact:true}).isDisabled());
  await page.getByRole('status').getByText('This report requires view access to its source transactions.').waitFor();
  assert.deepEqual(errors,[]);
  console.log('Verified invoice calculations, draft save, and reopened reference details');
}finally{
  await browser?.close();
  server.kill();
}
