import { isoDate } from './erp-utils.js';
import { normalizeReference, numberValue } from './workflow-integrity.js';
import { hasDocumentValue } from './document-data.js';

const aliases={
  Customer:['Customer','Prospect'],Vendor:['Vendor','Supplier'],Supplier:['Supplier','Vendor'],
  Product:['Product','Item','Material'],Item:['Item','Product','Material'],Material:['Material','Item','Product'],
  Qty:['Qty','Good Qty','Received Qty'], 'Received Qty':['Qty'], 'Taxable Amount':['Amount'],
  'Delivery Date':['Delivery','Required Date'],Delivery:['Expected Delivery','Delivery'],'PO Date':['Date'],
  'Work Order':['WO No'], 'Project Name':['Project Name/Code'], 'Project Name/Code':['Project Name']
};

export const allowedFetchRecord=(source,record)=>!source.statuses||source.statuses.includes(record.fields.Status||record.fields['QC Status']);
const valueFor=(fields,keys)=>keys.map(key=>fields[key]).find(hasDocumentValue);
export const fetchReferenceValue=(source,record)=>source.referenceValue?record.fields[source.referenceValue]:record.number;

export function referenceFetchValues(source,record,fields){
  const result={};
  for(const {key,label,type} of fields){
    if(source.omit?.includes(key))continue;
    const mapped=source.fields[key]||source.fields[label];
    const value=key===source.reference?fetchReferenceValue(source,record)
      :valueFor(record.fields,[mapped,key,label,...(aliases[key]||[])]);
    if(!hasDocumentValue(value))continue;
    const parsed=type==='date'?isoDate(value):value;
    if(hasDocumentValue(parsed))result[key]=parsed;
  }
  return result;
}

export function referenceSelectionConflict(source,record,form,prior){
  const name=source.relatedReference||source.reference;
  const binding=source.relatedReference?record.fields[name]:fetchReferenceValue(source,record);
  if(name&&hasDocumentValue(form[name])&&hasDocumentValue(binding)&&normalizeReference(form[name])!==normalizeReference(binding)){
    return `Clear ${name} before fetching a different source document.`;
  }
  if(prior&&!prior.field&&(prior.module!==source.module||normalizeReference(prior.number)!==normalizeReference(record.number))){
    return 'Start a new draft to fetch a different source for this document.';
  }
  return '';
}

export function sourceProvenance(source,record,form){
  const field=source.relatedReference||source.reference;
  return {module:source.module,number:record.number,...(field&&hasDocumentValue(form[field])?{field,value:form[field]}:{})};
}

export function activeSource(provenance,form){
  return !!provenance&&(!provenance.field||normalizeReference(form[provenance.field])===normalizeReference(provenance.value??provenance.number));
}

export function dispatchInvoiceSource(source,record){
  const fields=record.fields;
  const values=referenceFetchValues(source,record,[
    {key:'customer',label:'Customer'},{key:'sourceOrder',label:'Sales Order Reference'},
    {key:'dc',label:'DC Number'},{key:'po',label:'Buyer PO No.'},
    {key:'project',label:'Project Name'},{key:'vehicle',label:'Vehicle No.'},
    {key:'DC date',label:'DC date',type:'date'}
  ]);
  const product=hasDocumentValue(fields.Product)?fields.Product:fields.Item;
  const line=hasDocumentValue(product)?{
    description:product,code:fields['Product Code']||'',quantity:hasDocumentValue(fields.Qty)?String(fields.Qty):'',
    uom:hasDocumentValue(fields.UOM)?fields.UOM:'',
    rate:source.module==='Sales Orders'&&numberValue(fields.Rate)!==null?String(fields.Rate):'0'
  }:null;
  return {values,line};
}

export function verifyDispatchInvoice(form,lines,record,invoiceRecords,editing){
  const expected=numberValue(record.fields.Qty);
  const product=normalizeReference(record.fields.Product);
  const code=normalizeReference(record.fields['Product Code']);
  if(expected===null||expected<=0||(!product&&!code))return 'The source dispatch needs a saved product and positive quantity.';
  if(record.party&&normalizeReference(record.party)!==normalizeReference(form.customer))return 'Invoice customer must match the dispatch customer.';
  const match=line=>{
    const lineCode=normalizeReference(line.code);
    return code&&lineCode?code===lineCode:product===normalizeReference(line.description)||product===lineCode;
  };
  if(lines.some(line=>!match(line)))return 'Every invoice item must match the product on the selected dispatch.';
  let allocated=0;
  for(const invoice of invoiceRecords){
    if(normalizeReference(invoice.number)===normalizeReference(editing)||invoice.fields.Status==='REJECTED'
      ||normalizeReference(invoice.fields.dc||invoice.fields['DC Number'])!==normalizeReference(form.dc))continue;
    if(['Delivery Challan','Job Work Return DC'].includes(invoice.fetchedFrom?.module)
      &&invoice.fetchedFrom.module!==form.fetchedFrom.module)continue;
    if(!invoice.lines.length||invoice.lines.some(line=>!match(line)||numberValue(line.quantity)===null)){
      return 'An existing invoice for this dispatch needs verified line quantities before additional billing.';
    }
    allocated+=invoice.lines.reduce((sum,line)=>sum+numberValue(line.quantity),0);
  }
  const proposed=lines.reduce((sum,line)=>sum+(numberValue(line.quantity)??0),0);
  return allocated+proposed>expected+1e-8
    ?`Invoice quantity exceeds the remaining dispatch quantity (${Math.max(0,expected-allocated)}).`:'';
}
