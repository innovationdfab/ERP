import test from 'node:test';
import assert from 'node:assert/strict';
import {findRecord, recordToObject, normalizeReference, numberValue, validateConnectedRecord, resolveWorkflowContext} from '../src/workflow-integrity.js';

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
