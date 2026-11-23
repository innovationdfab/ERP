import test from 'node:test';
import assert from 'node:assert/strict';
import {productIndex,reorderRows,validateReorderPolicy,receivableRows,statementRows,validateFollowup,extensionAllowed} from '../src/erp-extensions.js';
const products=[['P1','Sheet','RAW MATERIAL','METAL','KG','R01','ACTIVE']];
const vendors=[['V1','Vendor','','','','','','','ACTIVE']];
const policy={id:'P1',minimum:5,target:20,vendor:'V1',leadDays:2,enabled:true};
const reader=records=>module=>records[module]||[];
test('replenishment subtracts unconverted indents, open PO balances and receipts awaiting QC',()=>{
 const readRows=reader({'dfab-erp-products-v3':products,'dfab-erp-Opening Stock':[['OP1','P1','Stores','3','10','Posted']]});
 const readDocuments=reader({
  'Purchase Orders':[{number:'PO1',fields:{Status:'Approved',Item:'Sheet',Qty:'10'}}],
  GRN:[{fields:{'PO No':'PO1','Received Qty':'4','QC Status':'Awaiting QC'}}],
  'Purchase Indents':[{fields:{Item:'P1',Qty:'2',Status:'Approval Pending'}},{fields:{Item:'P1',Qty:'50',Status:'Converted'}}]
 });
 const [row]=reorderRows([policy],readRows,readDocuments);
 assert.equal(row.stock,3);assert.equal(row.onOrder,6);assert.equal(row.requested,2);assert.equal(row.quantity,9);
 const [covered]=reorderRows([policy],readRows,reader({'Purchase Indents':[{fields:{Item:'P1',Qty:'17',Status:'Draft'}}]}));
 assert.equal(covered.quantity,0);
});
test('stock stays unassigned when product names are ambiguous and policies require valid active masters',()=>{
 const index=productIndex([...products,['P2','Sheet']]);
 assert.equal(index('Sheet'),null);assert.equal(index('P1')[0],'P1');
 assert.equal(validateReorderPolicy(policy,products,vendors),'');
 assert.match(validateReorderPolicy({...policy,target:5},products,vendors),/Target/);
 assert.match(validateReorderPolicy({...policy,leadDays:1.5},products,vendors),/whole number/);
 assert.match(validateReorderPolicy(policy,products,[]),/vendor/);
});
const finance=reader({
 'Sales Invoice':[{number:'SI1',fields:{Status:'APPROVED',Date:'2026-10-01',Customer:'Customer',Amount:'100'}}],
 'Customer Payments':[{fields:{Status:'Part Paid',Invoice:'SI1',Date:'2026-10-20',Amount:20}},
 {fields:{Status:'Settled',Invoice:'SI1',Date:'2026-12-01',Amount:25}},
 {fields:{Status:'Draft',Invoice:'SI1',Date:'2026-10-20',Amount:80}}],
 'Credit Note':[{fields:{Status:'Posted',Invoice:'SI1',Date:'2026-10-21',Amount:10}}]
});
const details=()=>({SI1:{form:{dueDate:'2026-10-15',currency:'INR'}}});
test('historical receivables reconcile dated posted receipts and credits without future or draft payments',()=>{
 const [row]=receivableRows(finance,details,'2026-11-23');
 assert.equal(row.balance,70);assert.equal(row.received,20);assert.equal(row.credited,10);
 assert.equal(row.bucket,'31–60 days');assert.equal(row.age,39);
 assert.equal(statementRows('Customer','USD',finance,details,'2026-11-23').length,0);
 assert.equal(statementRows('Customer','INR',finance,details,'2026-11-23')[0].balance,70);
 const [missing]=receivableRows(finance,()=>({}),'2026-11-23');
 assert.equal(missing.bucket,'Due date missing');
});
test('follow-up validates outstanding invoice and extension views fail closed on missing source access',()=>{
 const invoices=receivableRows(finance,details,'2026-11-23');
 const form={invoice:'SI1',nextDate:'2026-11-24',owner:'Accounts',channel:'Phone',status:'Open',note:'Call customer'};
 assert.equal(validateFollowup(form,invoices),'');
 assert.match(validateFollowup({...form,nextDate:'2026-02-30'},invoices),/date/);
 assert.match(validateFollowup(form,[{...invoices[0],balance:0}]),/outstanding/);
 assert.equal(validateFollowup({...form,status:'Done'},[{...invoices[0],balance:0}],true),'');
 assert.equal(extensionAllowed('Receivables Ageing',()=>true),true);
 assert.equal(extensionAllowed('Receivables Ageing',name=>name!=='Credit Note'),false);
});

test('reorder quantities retain decimal precision and linked PO indents are not counted twice',()=>{
 const rows=reader({'dfab-erp-products-v3':products,'dfab-erp-Opening Stock':[['OP','P1','Stores','3.125','10','Posted']]});
 const documents=reader({'Purchase Orders':[{number:'PO1',fields:{Status:'Approved',Item:'P1',Qty:'2',"Indent No":'PI1'}}],
  'Purchase Indents':[{number:'PI1',fields:{Status:'Approved',Item:'P1',Qty:'2'}}]});
 const [row]=reorderRows([policy],rows,documents);
 assert.equal(row.requested,0);assert.equal(row.onOrder,2);assert.equal(row.quantity,14.875);
});
