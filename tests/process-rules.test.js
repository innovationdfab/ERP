import test from 'node:test';
import assert from 'node:assert/strict';
import {lineAmounts,documentAmounts,validateDocument,canForward,paymentBalance,validatePayment,projectRow} from '../src/process-rules.js';
import {writeCloudValue} from '../src/backend/cloud-store.js';
import {paymentsFor,freshDocument,financialYear} from '../src/process-store.js';
import {SOP_FLOWS,schemas,nextStages} from '../src/process-schema.js';
const valid=module=>({...freshDocument(module),party:'DFAB Customer',header:{'Customer PO Dt.':'2026-11-01','C Number':'C1','A Number':'A1'},lines:[{code:'PART',description:'Part',quantity:'2',rate:'100',discount:'10',cgst:'9',sgst:'9',igst:'0'}],assignment:{department:'Sales / RFQ',user:'Kabil',due:'2026-12-20'},date:'2026-11-02'});
test('discount, split GST, charges and rounding use stored monetary totals',()=>{
 assert.deepEqual(lineAmounts(valid('Sales Orders').lines[0]),{base:200,discount:20,taxable:180,cgst:16.2,sgst:16.2,igst:0,gross:212.4});
 assert.equal(documentAmounts({...valid('Sales Orders'),charges:[{description:'Freight',amount:10,cgst:9,sgst:9,igst:0}],adjustment:-.2}).gross,224);
});
test('all SOP transaction stages resolve and labour begins with inward QC',()=>{
 for(const stages of Object.values(SOP_FLOWS))for(const stage of stages)assert.ok(schemas[stage]||stage==='Customer Payments');
 assert.deepEqual(SOP_FLOWS.labour.slice(0,3),['Job Work Inward','Inward QC','Sales Orders']);
 assert.equal(nextStages({...valid('Sales Orders'),flow:'manufacturing'})[0],'Purchase Orders');
 assert.equal(nextStages({...valid('Sales Orders'),flow:'labour'})[0],'Work Order');
});
test('release requires assignment, valid date, quantity and mutually exclusive tax split',()=>{
 const doc=valid('Sales Orders');assert.equal(validateDocument(doc),'');
 assert.match(validateDocument({...doc,assignment:{}}),/Assign/);
 assert.match(validateDocument({...doc,date:'2026-02-30'}),/date/);
 assert.match(validateDocument({...doc,lines:[{...doc.lines[0],quantity:0}]}),/quantity/);
 assert.match(validateDocument({...doc,lines:[{...doc.lines[0],igst:18}]}),/either/);
 assert.equal(validateDocument({...doc,assignment:{}},{draft:true}),'');
});
test('QC rejected lots and incomplete route operations cannot advance',()=>{
 const qc={...valid('Inward QC'),status:'PASSED',inspection:{inspector:'Mohan',result:'Rejected',accepted:1,rejected:1}};
 assert.match(canForward(qc,'Work Order'),/must pass/);
 const route={...valid('Route Cards'),status:'RELEASED',operations:[{process:'Weld',quantity:1,status:'Completed',qcRequired:true,qcStatus:'Pending'}]};
 assert.match(canForward(route,'Production Output'),/QC/);
 route.operations[0].qcStatus='Passed';assert.match(canForward(route,'Production Output'),/full order/);
 route.operations[0].quantity=2;assert.equal(canForward(route,'Production Output'),'');
});
test('QC quantity reconciliation rejects over-accepted and passed rejected quantities',()=>{
 const qc={...valid('Inward QC'),inspection:{inspector:'Mohan',result:'Passed',accepted:2,rejected:1}};
 assert.match(validateDocument(qc),/must equal/);qc.inspection.accepted=1;assert.match(validateDocument(qc),/cannot include/);
});
test('payment allocations include deductions, prevent overpayment and require reference',()=>{
 assert.equal(paymentBalance(118,[{amount:90,tds:10,ld:3}]),15);
 const p={date:'2026-11-02',type:'Online',reference:'REF',amount:15,tds:0,ld:0};assert.equal(validatePayment(p,15),'');
 assert.match(validatePayment({...p,amount:16},15),/exceed/);assert.match(validatePayment({...p,reference:''},15),/reference/);
});
test('legacy projections retain original row layout and financial year boundary',()=>{
 const doc={...valid('Sales Orders'),number:'SO/26-27/00001',status:'APPROVED',header:{'PO Number':'PO1'}};
 assert.deepEqual(projectRow(doc,['SO No','Customer','Customer PO','Product','Qty','Delivery','Status']),['SO/26-27/00001','DFAB Customer','PO1','PART','2','-','APPROVED']);
 assert.equal(projectRow({...valid('Purchase'),number:'IP1'},['Invoice No','Taxable Amount'])[1],'180');
 assert.equal(financialYear('2026-03-31'),'25-26');assert.equal(financialYear('2026-04-01'),'26-27');
});

test('existing payment allocations are preserved without double-counting compatibility rows',()=>{
 writeCloudValue('dfab-process-payments',[{id:'new',invoice:'I1',module:'Sales Invoice',amount:20,tds:0,ld:0}]);
 writeCloudValue('dfab-erp-Customer Payments',[['new','Customer','I1','2026-11-02',20,'Part Paid'],['old','Customer','I1','2026-10-30',30,'Settled'],['pending','Customer','I1','2026-11-01',40,'Pending']]);
 const payments=paymentsFor('I1','Sales Invoice');assert.equal(payments.length,2);assert.equal(paymentBalance(100,payments),50);
});
