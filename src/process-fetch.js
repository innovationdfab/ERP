import {schemas,nextStages} from './process-schema.js';
import {canForward} from './process-rules.js';

// Visible Pickup choices in the signed-in reference, inspected 2 Nov 2026.
// SOP sources remain available as well; the SOP graph itself is unchanged.
export const REFERENCE_FETCH_SOURCES={
 'Sales Quotations':['Sales Orders','Sales Enquiries'],
 'Sales Orders':['Sales Quotations','Job Work Inward'],
 'Purchase Orders':['Purchase Indents','Outsource Issue DC'],
 'GRN':['Purchase Orders'], 'Purchase':['GRN'],
 'Work Order':['Sales Orders','Rejection Note'],
 'Production Output':['Work Order'], 'Outward QC':['Production Output'],
 'Delivery Challan':['Sales Orders'], 'Sales Invoice':['Sales Orders'],
 'Proforma Invoice':['Sales Orders'], 'Sales Return':['Sales Invoice'],
 'Credit Note':['Sales Invoice'], 'Outsource Receipt':['Outsource Issue DC'],
 'Inward Quality':['Job Work Inward'], 'Material Issue':['Material Request']
};
export function fetchSourceTypes(target){
 const sop=Object.keys(schemas).filter(module=>!(target==='Work Order'&&module==='Inward QC')&&['manufacturing','labour'].some(flow=>[false,true].some(productionIncluded=>nextStages({module,flow,productionIncluded}).includes(target))));
 return [...new Set([...(REFERENCE_FETCH_SOURCES[target]||[]),...sop])];
}
export function fetchSourceIssue(source,target){
 if(!source||!fetchSourceTypes(target).includes(source.module))return 'This source type is not available for this transaction.';
 if(!['APPROVED','RELEASED','PASSED','COMPLETED','DISPATCHED','DELIVERED'].includes(String(source.status).toUpperCase()))return 'Approve or release the source first.';
 if(nextStages(source).includes(target)){const issue=canForward(source,target);if(issue)return issue;}
 if(source.legacy)return 'Review and save the original source line details before fetching this older summary record.';
 if(!source.lines?.length||source.lines.some(l=>!l.id||!(l.code?.trim()||l.description?.trim())||!Number.isFinite(Number(l.quantity))||Number(l.quantity)<=0))return 'Original source line details are missing. Complete the source first.';
 return '';
}
const sameSource=(doc,source)=>doc.source?.module===source.module&&doc.source?.number===source.number;
const active=doc=>doc.status!=='REJECTED';
export function fetchAvailability(source,target,documents,currentNumber=''){
 const children=documents.filter(d=>d.module===target&&d.number!==currentNumber&&sameSource(d,source)&&active(d));
 return source.lines.map(line=>{
  // Older Continue handoffs retained the original line id. New Fetch lines keep
  // that identity explicitly, even when two products share the same code.
  const picked=children.reduce((sum,d)=>sum+(d.lines||[]).filter(l=>(l.sourceLineId===line.id||l.id===line.id)).reduce((n,l)=>n+Number(l.quantity||0),0),0);
  return {line,quantity:Number(line.quantity),picked,pending:Math.max(0,Number(line.quantity)-picked)};
 });
}
const aliasGroups=[
 ['Project Name','Project Name/Code'],['PO Number','Buyer PO No.'],
 ['Customer PO Dt.','PO Date','Buyer Ref Date'],['Work Order Number','Work Order No','Work Order No.','WO No','Ref Work Order Number'],
 ['Invoice No.','Supplier Invoice No.','Vendor Invoice Number'],['Invoice Date','Supplier Invoice Dt.'],
 ['Terms of payment','Payment Terms'],['DC NO.','MGP/Customer DC No','MGP/Customer DC Number'],
 ['DC Date.','MGP/Customer DC Date','MGP/Customer Dc Date'],['Vehicle No.','Vehicle No'],
 ['E-Way Bill No','Eway Bill No','e-Way Bill No'],['E-Way Bill Date','Eway Bill Date']
];
const references={
 'Sales Enquiries':[['Enq Ref. No.'],['Enq Ref date.']],
 'Sales Quotations':[['Quotation No'],['Quotation Date']],
 'Sales Orders':[['SO Ref No','Sale Order No','Sale Order Number'],[]],
 'Purchase Orders':[['PO Ref No','Our Po No'],['PO Ref. Dt.']],
 'GRN':[['GRN No'],[]], 'Job Work Inward':[['Job Inward No'],[]],
 'Work Order':[['WO No','Work Order Number','Work Order No','Work Order No.','Ref Work Order Number','Ref WorkOrder No.'],[]],
 'Delivery Challan':[['DC Number'],['DC date']], 'Outsource Issue DC':[['Issue DC'],[]]
};
const supplierModules=new Set(['Purchase Orders','Purchase Indents','GRN','Purchase','Outsource Issue DC','Outsource Receipt','Inward QC','Inward Quality','Inward Quality Rejection']);
export function sourceUsesSameParty(source,target){
 // Reference labels call some customer job-work/dispatch accounts Vendor.
 const sourceSupplier=supplierModules.has(source.module)&&!(source.flow==='labour'&&['Inward QC','Inward Quality'].includes(source.module));
 const targetSupplier=supplierModules.has(target)&&!(source.flow==='labour'&&['Inward QC','Inward Quality'].includes(target));
 return sourceSupplier===targetSupplier;
}
export function applyFetch(target,source,selection,documents){
 const issue=fetchSourceIssue(source,target.module);if(issue)throw new Error(issue);
 if(target.number&&(source.references?.[target.module]===target.number||source.root?.module===target.module&&source.root?.number===target.number))throw new Error('This source would create a circular document link.');
 if(target.party&&source.party&&sourceUsesSameParty(source,target.module)&&target.party!==source.party)throw new Error('The source belongs to a different party. Choose a matching document or clear the party first.');
 const currency=source.header?.['Currency Type'];if(currency&&target.header?.['Currency Type']&&currency!==target.header['Currency Type'])throw new Error('Source and destination currencies must match.');
 const available=fetchAvailability(source,target.module,documents,target.number),lines=[];
 for(const {line,pending}of available){if(!Object.hasOwn(selection,line.id))continue;const quantity=Number(selection[line.id]);if(!Number.isFinite(quantity)||quantity<=0||quantity>pending+0.000001)throw new Error(`${line.code||line.description}: fetch quantity must be greater than zero and within pending quantity (${pending}).`);lines.push({...structuredClone(line),id:crypto.randomUUID(),sourceLineId:line.id,quantity:String(quantity)});}
 if(!lines.length)throw new Error('Select at least one pending source item.');
 const header={...target.header};
 for(const field of ['Tran Ref No','Ref Tran No','Reference Tran No'])if(schemas[target.module].fields.includes(field))header[field]=source.number;
 // Copy only fields used by the target. Assignment, inspection, attachments,
 // operations and target-specific remarks keep their own values.
 for(const field of schemas[target.module].fields){
  if(/remarks|next task|target date|approved by|purchased by|requested by/i.test(field))continue;
  const aliases=aliasGroups.find(group=>group.includes(field))||[field];
  const value=aliases.map(key=>source.header?.[key]).find(value=>value!==undefined&&value!==null&&value!=='');
  if(value!==undefined&&(header[field]===undefined||header[field]===''))header[field]=value;
 }
 for(const [module,number]of Object.entries({...source.references,[source.module]:source.number})){
  const upstream=documents.find(d=>d.module===module&&d.number===number)|| (module===source.module?source:null);
  const [numbers=[],dates=[]]=references[module]||[];
  for(const field of numbers)if(schemas[target.module].fields.includes(field))header[field]=number;
  for(const field of dates)if(upstream&&schemas[target.module].fields.includes(field))header[field]=upstream.date;
 }
 if(schemas[target.module].fields.includes('Invoice Category'))header['Invoice Category']=source.flow==='labour'?'Labour Job':'Manufacturing and Supply';
 return {...target,flow:source.flow,party:sourceUsesSameParty(source,target.module)?source.party:target.party,header,lines,source:{module:source.module,number:source.number},root:source.root||{module:source.module,number:source.number},references:{...source.references,[source.module]:source.number},assignedTo:structuredClone(source.assignment),fetch:{version:1,at:new Date().toISOString()}};
}
export function validateFetchedDocument(doc,documents){
 if(!doc.fetch)return '';
 const source=documents.find(d=>sameSource(doc,d));
 const issue=fetchSourceIssue(source,doc.module);if(issue)return issue;
 const availability=fetchAvailability(source,doc.module,documents,doc.number);
 const selected=doc.lines.filter(l=>l.sourceLineId);
 if(!selected.length)return 'Keep at least one fetched source line, or create a separate unlinked document.';
 for(const {line,pending}of availability){const matches=selected.filter(l=>l.sourceLineId===line.id);if(matches.some(l=>l.code!==line.code||l.uom!==line.uom))return 'Fetched product code and UOM must match the original source.';const qty=matches.reduce((sum,l)=>sum+Number(l.quantity),0);if(!Number.isFinite(qty)||qty>pending+0.000001)return `${line.code||line.description}: quantity exceeds the pending source quantity (${pending}).`;}
 if(selected.some(l=>!availability.some(a=>a.line.id===l.sourceLineId)))return 'A fetched source line is no longer available. Fetch the source again.';
 return '';
}
