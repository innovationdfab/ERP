import test from 'node:test';
import assert from 'node:assert/strict';
import {fetchSourceTypes,fetchSourceIssue,fetchAvailability,applyFetch,validateFetchedDocument} from '../src/process-fetch.js';
import {schemas,nextStages} from '../src/process-schema.js';
import {REFERENCE_FETCH_SOURCES} from '../src/process-fetch.js';
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

test('re-fetch refreshes automatically populated headers and party while preserving manual changes',()=>{
 const a=source(),first=applyFetch(target(),a,{a:2},[a]);
 const edited={...first,header:{...first.header,'Project Name':'Manual project'}};
 const b={...source(),number:'SO/2',party:'Customer B',header:{'Project Name/Code':'Project B','PO Number':'PO/B','Customer PO Dt.':'2026-11-01'}};
 const next=applyFetch(edited,b,{b:1},[a,b]);
 assert.equal(next.party,'Customer B');assert.equal(next.header['Buyer PO No.'],'PO/B');assert.equal(next.header['PO Date'],'2026-11-01');assert.equal(next.header['Project Name'],'Manual project');assert.equal(next.header['Vehicle No.'],'KEEP');assert.equal(next.header['C Number'],undefined);
 assert.equal(next.fetch.version,2);assert.equal(next.fetch.headerValues['Buyer PO No.'],'PO/B');assert.equal(next.fetch.headerValues['Project Name'],undefined);assert.equal(next.fetch.partyValue,'Customer B');assert.equal(first.party,'Customer A');assert.equal(first.header['Buyer PO No.'],'PO/CUST/1');
});
test('re-fetch still rejects a manually changed party or conflicting currency',()=>{
 const a=source(),first=applyFetch(target(),a,{a:1},[a]),b={...source(),number:'SO/2',party:'Customer B'};
 assert.throws(()=>applyFetch({...first,party:'Manual party'},b,{a:1},[a,b]),/different party/);
 assert.throws(()=>applyFetch({...first,header:{...first.header,'Currency Type':'USD'}},{...b,header:{'Currency Type':'INR'}},{a:1},[a,b]),/currencies/);
});
test('earlier Fetch metadata refreshes matching source values conservatively',()=>{
 const a=source(),first=applyFetch(target(),a,{a:1},[a]);first.fetch={version:1};
 const b={...source(),number:'SO/2',party:'Customer B',header:{'PO Number':'NEW-PO'}};
 const next=applyFetch(first,b,{a:2},[a,b]);assert.equal(next.header['Buyer PO No.'],'NEW-PO');assert.equal(next.party,'Customer B');assert.equal(next.header['Vehicle No.'],'KEEP');
});
test('fetch creates an editable draft with recalculated totals instead of retaining an old summary amount',()=>{
 const t={...target(),number:'INV/OLD',legacy:true,legacyRow:['keep original input'],total:999999,status:'APPROVED'};
 const next=applyFetch(t,source(),{a:2},[]);assert.equal(next.number,'INV/OLD');assert.equal(next.status,'DRAFT');assert.equal(next.total,234.2);assert.equal(next.legacy,undefined);assert.equal(next.legacyRow,undefined);assert.equal(t.total,999999);assert.equal(t.legacy,true);
});
test('Fetch respects flow-specific QC and route output choices',()=>{
 const qc={...source(),module:'Inward QC',status:'PASSED',inspection:{result:'Passed'}};
 assert.match(fetchSourceIssue(qc,'Sales Orders'),/next-stage flow/);
 assert.equal(fetchSourceIssue({...qc,flow:'labour'},'Sales Orders'),'');
 const route={...source(),module:'Route Cards',operations:[{status:'Completed',quantity:'14',qcRequired:true,qcStatus:'Passed'}]};
 assert.match(fetchSourceIssue(route,'Outward QC'),/next-stage flow/);
 assert.equal(fetchSourceIssue({...route,productionIncluded:true},'Outward QC'),'');
 assert.match(fetchSourceIssue({...route,productionIncluded:true},'Production Output'),/next-stage flow/);
});
test('every supported Fetch source transfers real item values and lineage through the shared model',()=>{
 let covered=0;
 for(const module of Object.keys(schemas))for(const kind of fetchSourceTypes(module)){
  let s={...source(),module:kind,number:`${kind}/TEST`,inspection:{result:'Passed'},operations:[{status:'Completed',quantity:'14',qcRequired:true,qcStatus:'Passed'}]};
  if(!(REFERENCE_FETCH_SOURCES[module]||[]).includes(kind)){
   const choices=['manufacturing','labour'].flatMap(flow=>[false,true].map(productionIncluded=>({...s,flow,productionIncluded})));
   s=choices.find(candidate=>nextStages(candidate).includes(module));assert.ok(s,`${kind} → ${module}`);
  }
  const next=applyFetch(freshDocument(module),s,{a:2},[s]);assert.equal(next.lines[0].code,'P1');assert.equal(next.lines[0].rate,'100');assert.equal(next.lines[0].quantity,'2');assert.equal(next.lines[0].drawing,'D1');assert.equal(next.source.module,kind);assert.equal(next.source.number,s.number);assert.equal(next.references[kind],s.number);assert.equal(next.status,'DRAFT');assert.equal(validateFetchedDocument(next,[s]),'');covered++;
 }
 assert.ok(covered>=20);
});

test('a fresh unassigned destination follows the fetched flow department and preserves existing assignments',()=>{
 const qc={...source(),module:'Inward QC',flow:'labour',status:'PASSED',inspection:{result:'Passed'}};
 const fresh=freshDocument('Sales Orders');assert.equal(fresh.assignment.department,'Finance / Purchase');
 assert.equal(applyFetch(fresh,qc,{a:2},[qc]).assignment.department,'Production / NPD');
 const assigned={...fresh,assignment:{...fresh.assignment,user:'Assigned buyer',due:'2026-12-01'}};
 assert.deepEqual(applyFetch(assigned,qc,{a:2},[qc]).assignment,assigned.assignment);
 const saved={...fresh,number:'SO/EXISTING'};assert.deepEqual(applyFetch(saved,qc,{a:2},[qc]).assignment,saved.assignment);
});
