import assert from 'node:assert/strict';
import test from 'node:test';
import {describeDocument,documentReportRows,invoiceColumns} from '../src/document-data.js';
import {stockReportRows} from '../src/imantra-stock.js';

test('saved and legacy invoice lines retain their own quantities and header amount',()=>{
  const line={description:'Steel',quantity:'2',uom:'NOS',rate:'50'};
  const row=['1','INV-1','2026-11-16','Acme','PO-1','Project','APPROVED','118','Pending','',JSON.stringify([line])];
  const legacy=describeDocument('Sales Invoice',invoiceColumns,row);
  assert.deepEqual(legacy.lines,[line]);
  const detail={form:{sourceOrder:'SO-1',taxRate:'18'},lines:[line]};
  const invoice=describeDocument('Sales Invoice',invoiceColumns,row,detail);
  assert.equal(invoice.fields['Sales Order Reference'],'SO-1');
  assert.deepEqual(documentReportRows('Sales Register',['Invoice No','Product','UOM','Qty','Net Amount'],
    ()=>[invoice],()=>({'INV-1':detail})),[['INV-1','Steel','NOS','2',118]]);
});

test('receivables reflect only posted receipts for the matching approved invoice',()=>{
  const sources={
    'Sales Invoice':[
      {number:'INV-1',fields:{Status:'APPROVED',Amount:'118.00'}},
      {number:'INV-DRAFT',fields:{Status:'DRAFT',Amount:'300'}}
    ],
    'Customer Payments':[
      {fields:{Invoice:'inv-1',Status:'Part Paid',Amount:'18.25'}},
      {fields:{Invoice:'INV-1',Status:'Pending',Amount:'99.75'}},
      {fields:{Invoice:'INV-other',Status:'Settled',Amount:'45'}}
    ]
  };
  assert.deepEqual(documentReportRows('Pending Receivables',['Invoice No','Received Amount','Balance Amount'],
    key=>sources[key]),[['INV-1',18.25,99.75]]);
});

test('open procurement quantities reflect accepted GRNs only',()=>{
  const sources={
    'Purchase Orders':[{number:'PO-1',fields:{'PO No':'PO-1',Status:'Approved',Item:'Steel',Qty:'25'}}],
    GRN:[
      {fields:{'PO No':'po-1','QC Status':'Accepted','Received Qty':'10'}},
      {fields:{'PO No':'PO-1','QC Status':'Awaiting QC','Received Qty':'15'}}
    ]
  };
  assert.deepEqual(documentReportRows('Pending Purchase Order to GRN',['PO No','Product','Order Qty','GRN Qty','Pending Qty'],
    key=>sources[key]),[['PO-1','Steel',25,10,15]]);
});

test('stock periods derive opening, movement and closing from confirmed records',()=>{
  const date=Date=>({version:1,header:{Date}});
  const sources={
    'dfab-erp-products-v3':[['ST-1','Steel','RAW','Metals','KG']],
    'dfab-erp-Opening Stock':[['OPEN-1','ST-1','Stores','20','10','Posted',date('2026-10-31')]],
    'dfab-erp-GRN':[
      ['GRN-1','PO-1','Supplier','Steel','5','Accepted',date('2026-11-02')],
      ['GRN-2','PO-1','Supplier','Steel','4','Awaiting QC',date('2026-11-03')]
    ],
    'dfab-erp-Material Issue':[['MI-1','WO-1','ST-1','2','Stores','Issued',date('2026-11-04')]]
  };
  const readRows=key=>sources[key]??[];
  const params={fromDate:'2026-11-01',toDate:'2026-11-30'};
  const cols=['Product Code','Opening Stock','Inward Qty','Outward Qty','Closing Stock','UOM','Value'];
  assert.deepEqual(stockReportRows('Stock Report',cols,readRows,{},params),[['ST-1',20,5,2,23,'KG','-']]);
  sources['dfab-erp-GRN'].push(['GRN-3','PO-1','Supplier','ST-1','8','Accepted']);
  assert.deepEqual(stockReportRows('Stock Report',cols,readRows,{},params),[['ST-1','-',5,2,'-','KG','-']]);
});
