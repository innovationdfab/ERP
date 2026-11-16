import test from 'node:test';
import assert from 'node:assert/strict';
import {findRecord, recordToObject, normalizeReference, numberValue, validateConnectedRecord, resolveWorkflowContext, validateProductionProgress, receiptPostingStatus, canRejectProductionDocument, nextProductionStatus} from '../src/workflow-integrity.js';

const rows={
  'Work Order': [{ 'WO No':'WO-1',Qty:'10',Product:'Plate','SO No':'SO-1' }],
  'Production Output': [{'Output No':'OUT-1','WO No':'WO-1','Good Qty':'8',Product:'Plate'}],
  'Sales Orders': [{'SO No':'SO-1',Customer:'DFAB',Qty:'10'}],
  'GRN': [{'GRN No':'GRN-1','Received Qty':'6',Item:'Steel',Vendor:'Vendor A'}],
  'Purchase': [{'Invoice No':'INV-1','Taxable Amount':'1,250.00'}],
  'Sales Invoice': [{'Invoice No':'SI-1',Amount:'2500'}],
  'Job Work Inward': [{'Inward No':'IN-1',Qty:'4'}],
  'Indent To Order': [{'Indent No':'IND-1',Item:'Steel',Qty:'6',Vendor:'Vendor A'}]
};
const lookup=(module,field,reference)=>rows[module]?.find(row=>normalizeReference(row[field])===normalizeReference(reference))||null;

test('reference joins match complete references, case-insensitively',()=>{
  assert.deepEqual(findRecord([['GRN-1','Steel']],['GRN No','Item'],'GRN No','grn-1'),['GRN-1','Steel']);
  assert.equal(findRecord([['GRN-1']],['GRN No'],'GRN No','GRN'),null);
  assert.deepEqual(recordToObject(['A','B'],[0,'X']),{A:0,B:'X'});
});
test('currency and number conversion is finite and cannot accept formulas',()=>{
  assert.equal(numberValue('₹ 1,250.50'),1250.5);
  assert.equal(numberValue('1+3'),null);
  assert.equal(numberValue('Infinity'),null);
  assert.equal(numberValue(''),null);
});
test('production output quantity cannot exceed work order',()=>{
  assert.match(validateConnectedRecord('Production Output',{'WO No':'WO-1','Good Qty':'9','Reject Qty':'2'},lookup),/cannot exceed/);
  assert.equal(validateConnectedRecord('Production Output',{'WO No':'WO-1','Good Qty':'8','Reject Qty':'2'},lookup),'');
});
test('qc and delivery quantities must match linked records',()=>{
  assert.match(validateConnectedRecord('Outward QC',{'Output No':'OUT-1',Qty:'9'},lookup),/cannot exceed/);
  assert.match(validateConnectedRecord('Inward QC',{'GRN No':'GRN-1',Qty:'7'},lookup),/cannot exceed/);
  assert.equal(validateConnectedRecord('Delivery Challan',{'SO No':'SO-1',Qty:'10'},lookup),'');
});
test('partial and final payments never exceed outstanding invoice value',()=>{
  const prior=[['PAY-1','Vendor A','INV-1','2026-10-01','600','Paid']];
  assert.match(validateConnectedRecord('Vendor Payments',{'Payment No':'PAY-2',Invoice:'INV-1',Amount:'700'},lookup,prior),/balance/);
  assert.equal(validateConnectedRecord('Vendor Payments',{'Payment No':'PAY-2',Invoice:'INV-1',Amount:'650'},lookup,prior),'');
  assert.equal(validateConnectedRecord('Customer Payments',{'Receipt No':'R-1',Invoice:'SI-1',Amount:'2500'},lookup,[]),'');
});
test('sales quotation fetches enquiry product and delivery',()=>{
  const get=(module,field,ref)=>module==='Sales Enquiries'&&ref==='ENQ-1'?{Product:'P1',Qty:'12','Expected Delivery':'2026-11-30'}:null;
  assert.deepEqual(resolveWorkflowContext('Sales Quotations',{Enquiry:'ENQ-1',Customer:'Acme'},get),{Enquiry:'ENQ-1',Customer:'Acme',Product:'P1',Qty:'12','Expected Delivery':'2026-11-30'});
});
test('outward qc connects production output, work order, sales order and customer',()=>{
  const result=resolveWorkflowContext('Delivery Challan',{'Output No':'OUT-1',Qty:'8'},lookup);
  assert.equal(result.Customer,'DFAB');assert.equal(result['SO No'],'SO-1');assert.equal(result.Product,'Plate');
});
test('purchase order uses linked indent-to-order to derive item and quantity',()=>{
  const result=resolveWorkflowContext('Purchase Orders',{'PO No':'PO-1',Vendor:'Vendor A'},lookup,[{from:'Indent To Order',reference:'IND-1',to:'Purchase Orders',created:'PO-1'}]);
  assert.equal(result.Item,'Steel');assert.equal(result.Qty,'6');
});

test('split production output reserves good and rejected quantities across saved records',()=>{
  const columns=['Output No','WO No','Product','Good Qty','Reject Qty','Status'];
  const prior=[['OUT-2','wo-1','Plate','5','1','Accepted'],['OUT-3','WO-1','Plate','10','0','Cancelled']];
  const form={'Output No':'OUT-4','WO No':'WO-1','Good Qty':'4','Reject Qty':'1',Status:'Draft'};
  assert.match(validateConnectedRecord('Production Output',form,lookup,prior,columns),/remaining quantity.*\(4\)/);
  assert.equal(validateConnectedRecord('Production Output',form,lookup,prior,columns,'OUT-2'),'');
});

test('multiple route operations may each cover the same work order quantity',()=>{
  const columns=['Route No','WO No','Operation','Machine','Completed Qty','Status'];
  const prior=[['RC-1','WO-1','Cut','M1','10','Completed']];
  const form={'Route No':'RC-2','WO No':'WO-1','Completed Qty':'10',Status:'Completed'};
  assert.equal(validateConnectedRecord('Route Cards',form,lookup,prior,columns),'');
});

test('production and receipts require complete source records before progress',()=>{
  assert.match(validateProductionProgress('Production Output',{'WO No':'MISSING'},lookup),/saved Work Order/);
  assert.match(validateProductionProgress('Production Output',{'WO No':'WO-1','Good Qty':'0','Reject Qty':'0'},lookup),/good or rejected quantity/);
  assert.equal(validateProductionProgress('Production Output',{'WO No':'WO-1','Good Qty':'0','Reject Qty':'1'},lookup),'');
  assert.match(validateProductionProgress('Customer Payments',{Invoice:'SI-1',Amount:'50'},lookup),/approved Sales Invoice/);
  assert.equal(validateProductionProgress('Customer Payments',{Invoice:'SI-1',Amount:'50'},()=>({Status:'APPROVED'})),'');
});

test('receipt posting distinguishes partial and settled invoice balances',()=>{
  const invoice={Amount:'100'};
  const prior=[['RE-1','Buyer','SI-1','2026-11-19','40','Part Paid'],['RE-2','Buyer','SI-1','2026-11-20','60','Pending']];
  const receipt={'Receipt No':'RE-2',Invoice:'SI-1',Amount:'59'};
  assert.equal(receiptPostingStatus(receipt,invoice,prior),'Part Paid');
  assert.equal(receiptPostingStatus({...receipt,Amount:'60'},invoice,prior),'Settled');
});

test('QC pass and rejection are alternative decisions',()=>{
  const statuses=['Pending','Passed','Rejected'];
  assert.equal(nextProductionStatus(statuses,'Pending'),'Passed');
  assert.equal(nextProductionStatus(statuses,'Passed'),undefined);
  assert.equal(canRejectProductionDocument('Inward QC','Pending'),true);
  assert.equal(canRejectProductionDocument('Inward QC','Passed'),false);
});

test('GRN acceptance and dispatch handoff use the QC and work order source records',()=>{
  assert.match(validateProductionProgress('GRN',{'GRN No':'GRN-1','QC Status':'Accepted'},lookup),/Pass Inward QC/);
  const receipt={'GRN No':'GRN-1','QC Status':'Accepted','Received Qty':'6'};
  assert.match(validateProductionProgress('GRN',receipt,()=>({Status:'Passed',Qty:'5'})),/must match/);
  assert.equal(validateProductionProgress('GRN',receipt,()=>({Status:'Passed',Qty:'6'})),'');
  const dispatch=resolveWorkflowContext('Outward QC',{'Output No':'OUT-1',Qty:'8'},lookup);
  assert.equal(dispatch.Customer,'DFAB');
  assert.equal(dispatch['SO No'],'SO-1');
  assert.equal(dispatch['WO No'],'WO-1');
});
