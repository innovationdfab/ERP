// Real invoice Fetch UI against an isolated Supabase fixture.
import assert from 'node:assert/strict';
import {launchFixture} from './browser-fixture.mjs';
const fixture=await launchFixture(5198);
const {page,store,open,errors}=fixture;
try {
  store.set('dfab-erp-Delivery Challan',[
    ['DC-QA','Fixture Customer','SO-QA','Fixture product','5','KA01','Delivered',{version:1,header:{'Product Code':'QA-P1',UOM:'NOS'}}],
    ['DC-DRAFT','Fixture Customer','SO-QA','Fixture product','5','KA01','Draft']
  ]);
  await page.evaluate(async()=>{const cloud=await import('/src/backend/cloud-store.js');await cloud.initializeCloudStore('fixture');});
  const create=async()=>{
    await open('Sales Invoice');
    await page.getByRole('button',{name:'Create new',exact:true}).click();
    await page.getByRole('button',{name:'Fetch',exact:true}).click();
    await page.locator('.reference-fetch-grid select').nth(0).selectOption({label:'Delivery Challan'});
    assert.equal(await page.locator('.reference-fetch-grid select').nth(1).locator('option').filter({hasText:'DC-DRAFT'}).count(),0);
    await page.locator('.reference-fetch-grid select').nth(1).selectOption('DC-QA');
    await page.getByRole('button',{name:'Fetch document',exact:true}).click();
    await page.getByLabel('Form sections').getByRole('button',{name:'Products',exact:true}).click();
  };
  await create();
  assert.equal(await page.getByLabel('Line 1 Description',{exact:true}).inputValue(),'Fixture product');
  assert.equal(await page.getByLabel('Line 1 Quantity',{exact:true}).inputValue(),'5');
  await page.getByLabel('Line 1 Rate',{exact:true}).fill('100');
  await page.getByRole('button',{name:'Save as Draft',exact:true}).click();
  await page.locator('.transaction-editor-page').waitFor({state:'hidden'});
  const invoices=store.get('dfab-erp-sales-invoices-v2');
  assert.equal(invoices.length,1);
  const saved=store.get('dfab-invoice-details-v1')[invoices[0][1]];
  assert.equal(saved.form.dc,'DC-QA');assert.equal(saved.form.sourceOrder,'SO-QA');
  assert.equal(saved.fetchedFrom.module,'Delivery Challan');
  await create();
  await page.getByLabel('Line 1 Rate',{exact:true}).fill('100');
  await page.getByRole('button',{name:'Save as Draft',exact:true}).click();
  await page.getByRole('alert').filter({hasText:'remaining dispatch quantity'}).waitFor();
  assert.equal(store.get('dfab-erp-sales-invoices-v2').length,1);
  assert.deepEqual(errors,[]);
  console.log('PASS: dispatch Fetch, eligible source filtering, order reference, saved lineage and duplicate billing protection.');
} finally {await fixture.close();}
