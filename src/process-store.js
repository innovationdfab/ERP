import {readStored,isoDate,todayISO} from './erp-utils.js';
import {exportCloudSnapshot,commitProcessChanges,nextProcessNumber} from './backend/cloud-store.js';
import {schemas,sideKey,rowKey,newLine,OWNERS,nextStages} from './process-schema.js';
import {validateFetchedDocument} from './process-fetch.js';
import {documentAmounts,projectRow,canForward,paymentBalance} from './process-rules.js';
let pendingOpen=null;
export function takePendingOpen(module){if(pendingOpen?.module===module){const result=pendingOpen;pendingOpen=null;return result;}return null;}
export function processDocuments(module,configs){
 const saved=readStored(sideKey(module),{}),config=configs[module];
 const docs=Object.values(saved||{});
 const rows=readStored(rowKey(module),[]);
 for(const row of rows){
  const invoice=module==='Sales Invoice',num=row[invoice?1:0];
  if(docs.some(d=>d.number===num))continue;
  const fields=invoice?['#','Invoice No','Date','Customer','Buyer PO No.','Project Name','Status','Amount']:config?.columns||[];
  const source=Object.fromEntries(fields.map((c,i)=>[c,row[i]]));
  const detail=invoice?readStored('dfab-invoice-details-v1',{})[num]:null;
  const invoiceHeader=detail?.form||{};
  const mappings={dc:'DC Number',po:'Buyer PO No.',vehicle:'Vehicle No.',project:'Project Name',terms:'Terms of payment',dispatch:'Mode of Dispatch',country:'Country of Shipment/Destination',attention:'Kind Attention',scope:'Scope Of Work',currency:'Currency Type'};
  const header={...source};for(const[k,v]of Object.entries(invoiceHeader))header[mappings[k]||k]=v;
  let lines=detail?.lines;
  if(!lines&&invoice&&row[10]){try{lines=JSON.parse(row[10]);}catch{/* Retain summary-only legacy invoices. */}}
  if(!lines){const product=source.Product||source.Item||source.Material;lines=product?[{...newLine(),code:product,description:product,quantity:source.Qty||source['Received Qty']||source['Good Qty']||'1'}]:[];}
  lines=lines.map((l,i)=>({...newLine(),...l,id:l.id||`${module}:${num}:line:${i}`,cgst:l.cgst??String(Number(invoiceHeader.taxRate??18)/2),sgst:l.sgst??String(Number(invoiceHeader.taxRate??18)/2)}));
  docs.push({module,number:num,flow:invoiceHeader.category==='Labour Job'?'labour':'manufacturing',party:source.Customer||source.Vendor||source.Supplier||source.Prospect||'',date:isoDate(source.Date||source['PO Date']||source['Invoice Date'])||todayISO(),series:invoiceHeader.series||schemas[module]?.series[0]||'',header,lines,charges:[],operations:[],status:String(source.Status||source['QC Status']||source.Stage||'DRAFT').toUpperCase(),assignment:{department:'',user:'',due:''},references:{},history:[],attachments:{},legacy:true,total:Number(source.Amount||source['Taxable Amount']||0),legacyRow:row});
 }
 return docs;
}
export function freshDocument(module,flow='manufacturing'){
 return {module,flow,number:'',date:todayISO(),series:schemas[module]?.series[0]||'',party:'',status:'DRAFT',header:{},lines:[newLine()],charges:[],operations:[],assignment:{department:OWNERS[nextStages({module,flow})[0]]||'',user:'',due:''},inspection:{inspector:'',result:'Pending',accepted:'0',rejected:'0',remarks:''},attachments:{},references:{},history:[],adjustment:'0'};
}
export function financialYear(date){const year=Number(date.slice(0,4))-(Number(date.slice(5,7))<4?1:0);return `${String(year).slice(-2)}-${String(year+1).slice(-2)}`;}
export function snapshotForEdit(){return structuredClone(exportCloudSnapshot());}
function setChange(changes,expected,snapshot,key,value){changes[key]=value;expected[key]=snapshot[key]??null;}
function addDocument(changes,expected,snapshot,doc,configs){
 const key=sideKey(doc.module),rowsKey=rowKey(doc.module);
 setChange(changes,expected,snapshot,key,{...(snapshot[key]||{}),[doc.number]:doc});
 const rows=snapshot[rowsKey]||[],invoice=doc.module==='Sales Invoice',idx=rows.findIndex(r=>r[invoice?1:0]===doc.number),row=projectRow(doc,configs[doc.module]?.columns||[],idx>=0?idx:rows.length);
 setChange(changes,expected,snapshot,rowsKey,idx>=0?rows.map((r,i)=>i===idx?row:r):[row,...rows]);
 if(invoice){
  const key='dfab-invoice-details-v1';
  const form={date:doc.date,series:doc.series,customer:doc.party,consignee:doc.header.Consignee||'',po:doc.header['Buyer PO No.']||'',project:doc.header['Project Name']||'',dc:doc.header['DC Number']||'',currency:doc.header['Currency Type']||'INR',...doc.header};
  setChange(changes,expected,snapshot,key,{...(snapshot[key]||{}),[doc.number]:{...(snapshot[key]?.[doc.number]||{}),form,lines:doc.lines,...documentAmounts(doc),total:doc.total}});
 }
}
export async function saveProcessDocument(input,configs,snapshot,action='save',extraDocs=[]){
 const doc=structuredClone(input);
 const fetchIssue=validateFetchedDocument(doc,allProcessDocuments(configs));if(fetchIssue)throw new Error(fetchIssue);
 doc.header={...doc.header,'Next Task Assigned to':doc.assignment?.user||'','Target Date':doc.assignment?.due||''};
 if(!doc.number){const code=schemas[doc.module].code,prefix=['Sales Enquiries','Sales Quotations','Sales Orders'].includes(doc.module)?`${code}/${doc.series}`:doc.module==='Sales Invoice'&&doc.series==='EXPORT'?'EXP':code;doc.number=await nextProcessNumber(doc.module,prefix,financialYear(doc.date));}
 doc.total=documentAmounts(doc).gross;
 doc.updatedAt=new Date().toISOString();
 doc.history=[...(doc.history||[]),{action,status:doc.status,at:doc.updatedAt}];delete doc.legacy;delete doc.legacyRow;
 const changes={},expected={};
 if(doc.fetch&&doc.source){
  // Lock both source payloads alongside the target to reject source changes
  // and concurrent reservations using the existing atomic compare-and-swap.
  for(const key of [sideKey(doc.source.module),rowKey(doc.source.module)])setChange(changes,expected,snapshot,key,snapshot[key]??null);
  const key='dfab-workflow-links-v1',links=(snapshot[key]||[]).filter(l=>!(l.to===doc.module&&l.created===doc.number));
  setChange(changes,expected,snapshot,key,[...links,{from:doc.source.module,reference:doc.source.number,to:doc.module,created:doc.number,at:doc.updatedAt}]);
 }
 addDocument(changes,expected,snapshot,doc,configs);for(const extra of extraDocs)addDocument(changes,expected,snapshot,extra,configs);
 await commitProcessChanges(changes,expected,action);return doc;
}
export async function forwardProcessDocument(doc,target,configs){
 const issue=canForward(doc,target);if(issue)throw new Error(issue);
 const all=processDocuments(target,configs),existing=all.find(d=>d.source?.module===doc.module&&d.source?.number===doc.number);
 if(existing){pendingOpen={module:target,number:existing.number,edit:true};return existing;}
 const targetDoc=freshDocument(target,doc.flow),number=await nextProcessNumber(target,schemas[target]?.code||'DOC',financialYear(todayISO()));
 Object.assign(targetDoc,{number,party:doc.party,lines:structuredClone(doc.lines),header:{...doc.header},source:{module:doc.module,number:doc.number},root:doc.root||{module:doc.module,number:doc.number},references:{...doc.references,[doc.module]:doc.number},assignedTo:doc.assignment});
 const sourceFields={'Sales Enquiries':'Enq Ref. No.','Sales Quotations':'Quotation No','Sales Orders':'SO Ref No','Work Order':'WO No','Purchase Orders':'PO Ref No','GRN':'GRN No','Job Work Inward':'Job Inward No','Production Output':'Output No','Delivery Challan':'DC Number','Outsource Issue DC':'Issue DC'};
 if(sourceFields[doc.module])targetDoc.header[sourceFields[doc.module]]=doc.number;
 if(target==='Work Order')targetDoc.header['SO Ref No']=doc.references['Sales Orders']||doc.number;
 if(target==='Production Output')targetDoc.header['Ref Work Order Number']=doc.references['Work Order']||doc.number;
 if(target==='Purchase Orders'){targetDoc.party='';targetDoc.header.Customer=doc.party;}
 if(target==='Work Order'){const order=processDocuments('Sales Orders',configs).find(d=>d.number===doc.references?.['Sales Orders']);if(order){targetDoc.party=order.party;targetDoc.lines=structuredClone(order.lines);}}
 targetDoc.header['Invoice Category']=doc.flow==='labour'?'Labour Job':'Manufacturing and Supply';
 targetDoc.total=documentAmounts(targetDoc).gross;
 const snapshot=snapshotForEdit(),changes={},expected={};
 addDocument(changes,expected,snapshot,targetDoc,configs);
 const linksKey='dfab-workflow-links-v1',links=snapshot[linksKey]||[];
 if(links.some(l=>l.from===doc.module&&l.reference===doc.number&&l.to===target))throw new Error('A linked document already exists. Refresh the register.');
 setChange(changes,expected,snapshot,linksKey,[...links,{from:doc.module,reference:doc.number,to:target,created:number,at:new Date().toISOString()}]);
 await commitProcessChanges(changes,expected,'handoff');pendingOpen={module:target,number,edit:true};return targetDoc;
}
export function allProcessDocuments(configs){return Object.keys(schemas).flatMap(name=>processDocuments(name,configs));}
export function paymentsFor(invoice,module){
 const current=(readStored('dfab-process-payments',[])||[]).filter(p=>p.invoice===invoice&&p.module===module),known=new Set(current.map(p=>p.id));
 const key=module==='Purchase'?'dfab-erp-Vendor Payments':'dfab-erp-Customer Payments';
 const legacy=readStored(key,[]).filter(r=>r[2]===invoice&&!known.has(r[0])&&(module==='Purchase'?String(r[5]).toLowerCase()==='paid':!/^pending|rejected|draft/i.test(String(r[5])))).map(r=>({id:r[0],module,invoice,party:r[1],date:isoDate(r[3]),amount:Number(r[4])||0,tds:0,ld:0,type:'Legacy',reference:r[0],remarks:'Original payment record'}));
 return [...current,...legacy];
}
export function outstanding(doc){return paymentBalance(doc.total??documentAmounts(doc).gross,paymentsFor(doc.number,doc.module));}
export function requestProcessOpen(module,number){pendingOpen={module,number};}

export async function deleteProcessDocument(doc){
 const snapshot=snapshotForEdit(),links=snapshot['dfab-workflow-links-v1']||[];
 if(links.some(l=>l.reference===doc.number||l.created===doc.number))throw new Error('Linked documents cannot be deleted.');
 if(paymentsFor(doc.number,doc.module).length)throw new Error('An invoice with payment allocations cannot be deleted.');
 const key=sideKey(doc.module),rowsKey=rowKey(doc.module),saved={...(snapshot[key]||{})};delete saved[doc.number];
 const changes={[key]:saved,[rowsKey]:(snapshot[rowsKey]||[]).filter(r=>r[doc.module==='Sales Invoice'?1:0]!==doc.number)},expected={[key]:snapshot[key]??null,[rowsKey]:snapshot[rowsKey]??null};
 if(doc.module==='Sales Invoice'){const details='dfab-invoice-details-v1',next={...(snapshot[details]||{})};delete next[doc.number];changes[details]=next;expected[details]=snapshot[details]??null;}
 await commitProcessChanges(changes,expected,'delete');
}
