import test from 'node:test';
import assert from 'node:assert/strict';
import {fetchSourceTypes,fetchSourceIssue,fetchAvailability,applyFetch,validateFetchedDocument} from '../src/process-fetch.js';
import {freshDocument} from '../src/process-store.js';
const source=()=>({...freshDocument('Sales Orders'),number:'SO/1',party:'Customer A',status:'APPROVED',date:'2026-11-02',header:{'Project Name/Code':'Project A','PO Number':'PO/CUST/1','Customer PO Dt.':'2026-10-31','C Number':'C1'},assignment:{user:'Source user',department:'Accounts',due:'2026-11-03'},lines:[{id:'a',code:'P1',description:'Part',quantity:'10',uom:'Nos',rate:'100',discount:'5',cgst:'9',sgst:'9',igst:'0',drawing:'D1'},{id:'b',code:'P1',description:'Same code, other drawing',quantity:'4',uom:'Nos',rate:'50',cgst:'9',sgst:'9',igst:'0',drawing:'D2'}]});
const target=()=>({...freshDocument('Sales Invoice'),assignment:{user:'Target user',department:'Accounts',due:'2026-12-01'},header:{'Vehicle No.':'KEEP'},attachments:{file:'keep'},charges:[{amount:10}]});
test('reference source choices and existing SOP alternatives are both available',()=>{
 assert.deepEqual(fetchSourceTypes('Sales Quotations'),['Sales Orders','Sales Enquiries']);
 assert.ok(fetchSourceTypes('Sales Orders').includes('Inward QC'));
 assert.ok(fetchSourceTypes('Sales Invoice').includes('Delivery Challan'));
 assert.ok(fetchSourceTypes('Purchase Orders').includes('Outsource Issue DC'));
 assert.deepEqual(fetchSourceTypes('Opening Stock'),[]);
});
test('fetch copies selected item quantity, tax, drawing and aliases without sharing mutable objects',()=>{
 const s=source(),t=target(),d=applyFetch(t,s,{a:3},[s]);
 assert.equal(d.lines.length,1);assert.equal(d.lines[0].quantity,'3');assert.equal(d.lines[0].sourceLineId,'a');assert.notEqual(d.lines[0].id,'a');assert.equal(d.lines[0].drawing,'D1');assert.equal(d.lines[0].rate,'100');assert.equal(d.lines[0].discount,'5');assert.equal(d.lines[0].cgst,'9');
 assert.equal(d.header['Buyer PO No.'],'PO/CUST/1');assert.equal(d.header['Project Name'],'Project A');assert.equal(d.header['PO Date'],'2026-10-31');assert.equal(d.header['Vehicle No.'],'KEEP');assert.equal(d.party,s.party);assert.equal(d.references['Sales Orders'],'SO/1');
 assert.deepEqual(d.assignment,t.assignment);assert.deepEqual(d.attachments,t.attachments);assert.deepEqual(d.charges,t.charges);assert.equal(s.lines[0].quantity,'10');assert.equal(t.lines[0].code,'');d.lines[0].drawing='CHANGED';assert.equal(s.lines[0].drawing,'D1');
});
test('pending quantities track line identity, partial drafts and older Continue handoffs per target stage',()=>{
 const s=source(),child=applyFetch(target(),s,{a:3},[s]);child.number='INV/1';
 const old={...target(),number:'INV/2',source:{module:s.module,number:s.number},lines:[{...s.lines[0],sourceLineId:'older-parent',quantity:'2'}]};
 const rejected={...child,number:'INV/3',status:'REJECTED'};
 const quote={...child,module:'Sales Quotations',number:'SQ/1'};
 const a=fetchAvailability(s,'Sales Invoice',[s,child,old,rejected,quote]);assert.equal(a[0].picked,5);assert.equal(a[0].pending,5);assert.equal(a[1].pending,4);
 assert.equal(fetchAvailability(s,'Sales Invoice',[s,child,old],'INV/1')[0].pending,8);
});
test('fetch rejects empty, zero, non-finite and excessive selection quantities',()=>{
 for(const selected of [{},{a:0},{a:-1},{a:'NaN'},{a:11}])assert.throws(()=>applyFetch(target(),source(),selected,[]));
});
test('source release gates, missing lines, failed QC and route completion gates are respected',()=>{
 assert.match(fetchSourceIssue({...source(),status:'DRAFT'},'Sales Invoice'),/release/);
 assert.match(fetchSourceIssue({...source(),legacy:true},'Sales Invoice'),/Review and save/);
 assert.match(fetchSourceIssue({...source(),lines:[]},'Sales Invoice'),/missing/);
 assert.match(fetchSourceIssue({...source(),module:'Outward QC',inspection:{result:'Rejected'}},'Delivery Challan'),/pass/);
 assert.match(fetchSourceIssue({...source(),module:'Route Cards',operations:[{status:'Pending'}]},'Production Output'),/Complete/);
});
test('party, currency and circular link conflicts require reconciliation',()=>{
 assert.throws(()=>applyFetch({...target(),party:'Other'},source(),{a:1},[]),/different party/);
 assert.throws(()=>applyFetch({...target(),header:{'Currency Type':'USD'}},{...source(),header:{'Currency Type':'INR'}},{a:1},[]),/currencies/);
 assert.throws(()=>applyFetch({...target(),number:'INV/1'},{...source(),references:{'Sales Invoice':'INV/1'}},{a:1},[]),/circular/);
});
test('customer data does not become supplier on a purchasing source fetch',()=>{
 const t={...freshDocument('Purchase Orders'),party:'Selected supplier'},s={...source(),module:'Sales Orders'};
 const d=applyFetch(t,s,{a:1},[s]);assert.equal(d.party,'Selected supplier');
});
test('document number and dates populate destination reference fields',()=>{
 const s={...source(),module:'Purchase Orders',number:'PO/1'},t=freshDocument('GRN'),d=applyFetch(t,s,{a:2},[s]);assert.equal(d.header['PO Ref No'],'PO/1');assert.equal(d.header['PO Ref. Dt.'],'2026-11-02');
 const q={...source(),module:'Sales Quotations',number:'SQ/1'},o=applyFetch(freshDocument('Sales Orders'),q,{b:1},[q]);assert.equal(o.header['Quotation No'],'SQ/1');assert.equal(o.header['Quotation Date'],'2026-11-02');
});
test('save rechecks reservations, released status, source line identity, code and UOM',()=>{
 const s=source(),d=applyFetch(target(),s,{a:8},[s]);assert.equal(validateFetchedDocument(d,[s]),'');
 const other={...applyFetch(target(),s,{a:3},[s]),number:'INV/OTHER'};
 assert.match(validateFetchedDocument(d,[s,other]),/exceeds/);
 assert.match(validateFetchedDocument(d,[{...s,status:'REJECTED'}]),/release/);
 assert.match(validateFetchedDocument({...d,lines:d.lines.map(l=>({...l,code:'WRONG'}))},[s]),/code and UOM/);
 assert.match(validateFetchedDocument({...d,lines:d.lines.map(l=>({...l,sourceLineId:'missing'}))},[s]),/no longer/);
 assert.equal(validateFetchedDocument({...d,fetch:undefined},[]),'');
});
