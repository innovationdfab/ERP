// Reference header parity and complete transaction editors against isolated data.
import assert from 'node:assert/strict';
import {launchFixture} from './browser-fixture.mjs';
import {schemas} from '../src/process-schema.js';
import {fetchSourceTypes} from '../src/process-fetch.js';
const f=await launchFixture(5184);const {page,store,open,errors}=f;
try{
 const entries=Object.entries(schemas).slice(process.env.ERP_FORM_START?Object.keys(schemas).indexOf(process.env.ERP_FORM_START):0);
 for(const [title,schema]of entries){
  console.log('Checking',title);
  await open(title);await page.getByRole('button',{name:'Create new',exact:true}).click();
  assert.equal(await page.getByRole('dialog').count(),0,`${title}: create form must be inline`);
  const nav=page.getByRole('navigation',{name:'Form sections',exact:true});await nav.getByRole('button',{name:'Details',exact:true}).click();
  for(const label of ['Process','Date','Series','Document No.',...(schema.party?[schema.party]:[]),...schema.fields])assert.ok(await page.locator('.process-document-panel label').filter({has:page.locator('span').getByText(label,{exact:true})}).count(),`${title}: missing ${label}`);
  for(const button of await page.getByRole('navigation',{name:'Header field pages',exact:true}).getByRole('button').all())await button.click();
  await nav.getByRole('button',{name:'Items',exact:true}).click();
  for(const label of ['code','description','quantity','uom','rate','discount','cgst','sgst','igst','hsn','drawing','revision'])assert.equal(await page.getByLabel(`Line 1 ${label}`,{exact:true}).count(),1,`${title}: ${label}`);
  await page.getByRole('button',{name:'Add Line Item',exact:true}).click();assert.equal(await page.getByLabel('Line 2 quantity',{exact:true}).count(),1);await page.getByRole('button',{name:'Remove line 2',exact:true}).click();
  await page.getByRole('tab',{name:'Charges',exact:true}).click();await page.getByRole('button',{name:'Add charge',exact:true}).click();await page.getByLabel('Charges 1 description',{exact:true}).fill('Freight');await page.getByLabel('Charges 1 amount',{exact:true}).fill('10');
  await page.getByRole('button',{name:'Remove Charges 1',exact:true}).click();
  await nav.getByRole('button',{name:'Assignment',exact:true}).click();assert.equal(await page.getByLabel('Next responsible user',{exact:true}).count(),1);
  if(fetchSourceTypes(title).length){await page.getByRole('button',{name:'Fetch',exact:true}).click();const picker=page.getByRole('dialog',{name:`Fetch into ${title}`,exact:true});await picker.waitFor();assert.equal(await picker.getByRole('columnheader',{name:'Pending',exact:true}).count(),1);assert.equal(await picker.getByRole('columnheader',{name:'Fetch Qty',exact:true}).count(),1);await page.getByRole('button',{name:'Close Fetch',exact:true}).click();}
  // A fresh document can be cancelled without a native popup. These edits need confirmation.
  await page.getByRole('button',{name:'Back to register',exact:true}).click();const confirm=page.getByRole('alertdialog',{name:'Please confirm',exact:true});if(await confirm.count())await confirm.getByRole('button',{name:'Confirm',exact:true}).click();
  // Reopen to verify the draft/save/read/reload contract for every upgraded module.
  await page.getByRole('button',{name:'Create new',exact:true}).waitFor();await page.getByRole('button',{name:'Create new',exact:true}).click();
  if(schema.party){const field=page.locator('.process-document-panel').getByLabel(schema.party,{exact:true});await field.fill('QA parity customer');}
  await nav.getByRole('button',{name:'Items',exact:true}).click();await page.getByLabel('Line 1 description',{exact:true}).fill('Parity part');await page.getByLabel('Line 1 quantity',{exact:true}).fill('2');await page.getByLabel('Line 1 rate',{exact:true}).fill('100');
  await page.getByRole('button',{name:'Save as Draft',exact:true}).click();await page.getByRole('button',{name:'Edit',exact:true}).waitFor();
  const saved=Object.values(store.get(`dfab-process-${title}`)||{}).find(d=>d.lines.some(l=>l.description==='Parity part'));assert.ok(saved,`${title}: persisted sidecar`);assert.equal(saved.total,236);assert.ok(saved.number);
  assert.deepEqual(errors,[]);console.log('PASS FORM',title,schema.fields.length,'header fields + products/charges/assignment/Fetch/draft persistence');
 }
 await page.reload();await page.locator('.command-launcher').waitFor();await open(entries.find(([,schema])=>schema.party)[0]);assert.match(await page.locator('main').innerText(),/QA parity customer/);console.log(`Verified ${Object.keys(schemas).length} inline transaction forms and persisted reload.`);
}catch(e){await page.screenshot({path:'test-results/form-parity-failure.png'});console.log(await page.locator('main').innerText());throw e;}finally{await f.close();}
