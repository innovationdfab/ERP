import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {TRANSACTION_SECTIONS,transactionSection,transactionPath,transactionContext} from '../src/transaction-context.js';
import {schemas,nextStages} from '../src/process-schema.js';
import {fetchSourceTypes} from '../src/process-fetch.js';

test('transaction subsections cover the existing menu without adding routes',()=>{
 const text=fs.readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
 const start=text.indexOf("{ label:'Transactions', icon:FileText, children:["),end=text.indexOf("{ label:'Reports', icon:FileText, children:[",start);
 const menu=[...text.slice(start,end).matchAll(/\['([^']+)',[A-Za-z0-9]+\]/g)].map(m=>m[1]);
 assert.deepEqual(['SOP Workflow',...Object.values(TRANSACTION_SECTIONS).flat()],menu);
 for(const module of Object.keys(schemas))assert.ok(transactionSection(module),module);
 assert.deepEqual(transactionPath('Sales Orders'),['Transactions','Marketing','Sales Orders']);
 assert.deepEqual(transactionPath('Customer Payments'),['Transactions','Payments','Customer Payments']);
});
test('context preserves the manufacturing, labour, material and outsourcing branches',()=>{
 for(const module of Object.keys(schemas))for(const flow of ['manufacturing','labour']){
  const doc={module,flow},copy=structuredClone(doc),context=transactionContext(doc);
  assert.deepEqual(context.next,nextStages(doc));assert.deepEqual(context.sources,fetchSourceTypes(module));assert.deepEqual(doc,copy);
 }
 assert.deepEqual(transactionContext({module:'Sales Orders',flow:'manufacturing'}).next,['Purchase Orders']);
 assert.deepEqual(transactionContext({module:'Sales Orders',flow:'labour'}).next,['Work Order']);
 assert.deepEqual(transactionContext({module:'Work Order',flow:'manufacturing'}).next,['Route Cards','Material Request','Outsource Issue DC']);
});
test('stock pages do not imply that they are manufacturing milestones',()=>{
 for(const module of ['Opening Stock','Excess Stock','Shortage Stock','Scrap Entry']){
  const context=transactionContext({module,flow:'manufacturing'});
  assert.equal(context.process,'');assert.equal(context.sourceText,'Manual entry');assert.deepEqual(context.next,[]);assert.equal(context.nextText,'No next transaction');
 }
});
test('actual source identity is displayed instead of a guessed predecessor',()=>{
 const context=transactionContext({module:'Sales Invoice',flow:'manufacturing',source:{module:'Sales Orders',number:'SO/LOC/26-27/1'}});
 assert.equal(context.sourceText,'Sales Orders · SO/LOC/26-27/1');assert.equal(context.section,'Sales');assert.deepEqual(context.next,['Customer Payments']);
});
test('route-card output inclusion and return/credit paths retain their existing behavior',()=>{
 assert.deepEqual(transactionContext({module:'Route Cards',flow:'labour',productionIncluded:true}).next,['Outward QC','Outsource Issue DC']);
 assert.deepEqual(transactionContext({module:'Sales Return',flow:'manufacturing'}).next,['Credit Note']);
 assert.deepEqual(transactionContext({module:'Purchase',flow:'manufacturing'}).next,['Vendor Payments']);
});

test('older linked summaries recover the saved source for display without changing the record',()=>{
 const doc={module:'Sales Enquiries',flow:'manufacturing',number:'SE/1'},links=[{from:'CRM Pipeline',reference:'LEAD/1',to:'Sales Enquiries',created:'SE/1'}];
 assert.equal(transactionContext(doc,links).sourceText,'CRM Pipeline · LEAD/1');assert.equal(doc.source,undefined);
 assert.equal(transactionContext({...doc,source:{module:'Job Work Inward',number:'JI/2'}},links).sourceText,'Job Work Inward · JI/2');
});
