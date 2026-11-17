import assert from 'node:assert/strict';
import test from 'node:test';
import {activeSource, allowedFetchRecord, dispatchInvoiceSource, referenceFetchValues, sourceProvenance, verifyDispatchInvoice} from '../src/document-fetch.js';
import {operationRows, connectedOperations} from '../src/operations-views.js';
import {referenceFetch} from '../src/reference-forms.js';

test('PO Fetch copies receipt reference and product details while omitting actuals',()=>{
  const [rule]=referenceFetch.GRN;
  const record={number:'PO100',fields:{Status:'Approved',Vendor:'Steel Vendor',Item:'Sheet',Qty:'20',Rate:'25','PO Date':'2026-11-02'}};
  const keys=['PO No','Vendor','Item','Received Qty','Rate','PO Ref. Dt.'];
  const values=referenceFetchValues(rule,record,keys.map(key=>({key,type:key.endsWith('Dt.')?'date':'text'})));
  assert.deepEqual(values,{'PO No':'PO100',Vendor:'Steel Vendor',Item:'Sheet','PO Ref. Dt.':'2026-11-02'});
  assert.equal(allowedFetchRecord(rule,record),true);
  assert.equal(allowedFetchRecord(rule,{...record,fields:{...record.fields,Status:'Draft'}}),false);
});

test('dispatch billing checks customer, product, edited references and aggregate allocated quantity',()=>{
  const rule=referenceFetch['Sales Invoice'].find(candidate=>candidate.module==='Delivery Challan');
  const record={number:'DC-17',party:'Customer A',fields:{Status:'Delivered',Customer:'Customer A','SO No':'SO-2',Product:'Sheet','Product Code':'RM-5',Qty:'5',UOM:'KG'}};
  const {values,line}=dispatchInvoiceSource(rule,record);
  assert.equal(values.dc,'DC-17');
  assert.equal(values.sourceOrder,'SO-2');
  assert.equal(line.quantity,'5');
  const form={...values,fetchedFrom:sourceProvenance(rule,record,values)};
  const allocated={number:'INV-1',fields:{Status:'APPROVED',dc:'DC-17'},lines:[{code:'RM-5',quantity:'2'}]};
  const rejected={...allocated,number:'INV-3',fields:{...allocated.fields,Status:'REJECTED'}};
  assert.equal(activeSource(form.fetchedFrom,form),true);
  assert.equal(activeSource(form.fetchedFrom,{...form,dc:''}),false);
  assert.equal(verifyDispatchInvoice(form,[{...line,quantity:'3'}],record,[allocated,rejected]),'');
  assert.match(verifyDispatchInvoice(form,[{...line,quantity:'4'}],record,[allocated]),/remaining dispatch quantity \(3\)/);
  assert.equal(verifyDispatchInvoice(form,[line],record,[allocated],'INV-1'),'');
  assert.match(verifyDispatchInvoice({...form,customer:'Other'},[line],record,[]),/customer must match/);
  assert.match(verifyDispatchInvoice(form,[{...line,code:'OTHER'}],record,[]),/item must match/);
});

test('overdue register counts posted receipts and skips invoices without a saved due date',()=>{
  const invoices=['INV-1','INV-2','INV-3','INV-4'].map(number=>({number,fields:{Customer:'A',Amount:100,Status:'APPROVED'}}));
  const readDocuments=module=>module==='Sales Invoice'?invoices:[
    {fields:{Invoice:'INV-1',Amount:30,Status:'Part Paid'}},
    {fields:{Invoice:'INV-1',Amount:25,Status:'Draft'}},
    {fields:{Invoice:'INV-4',Amount:100,Status:'Settled'}}
  ];
  const readObject=()=>({
    'INV-1':{form:{dueDate:'2026-11-12',currency:'INR'}},
    'INV-3':{form:{dueDate:'2026-11-17'}},
    'INV-4':{form:{dueDate:'2026-11-10'}}
  });
  assert.deepEqual(operationRows('Customer Payment Overdue',{readDocuments,readObject,today:'2026-11-17'}),[
    {values:['INV-1','A','2026-11-12',5,100,30,70,'INR'],module:'Sales Invoice',reference:'INV-1'}
  ]);
});

test('related document actions respect source permissions',()=>{
  const readDocuments=module=>{
    assert.notEqual(module,'GRN');
    return [{number:'PO-1',fields:{},fetchedFrom:{module:'Purchase Indents',number:'PI-1'}}];
  };
  assert.deepEqual(connectedOperations('Purchase Orders','PO-1',[{from:'Purchase Orders',reference:'PO-1',to:'GRN',created:'GRN-1'}],
    readDocuments,module=>module==='Purchase Orders'),[]);
});
