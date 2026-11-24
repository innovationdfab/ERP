import {isoDate} from './erp-utils.js';
import {schemas} from './process-schema.js';

// Recover only explicitly saved original values, never today's date or INR.
export function recoverInvoiceHeader(header={},form={}){
 const result={...header};
 for(const [field,key]of [['Date','date'],['Due Date','dueDate'],['Credit Days','creditDays'],['Currency Type','currency']]){
  if((result[field]===undefined||result[field]===null||result[field]==='')&&form[key]!==undefined&&form[key]!==null&&form[key]!=='')result[field]=form[key];
 }
 return result;
}
export function reconciliationIssues(doc){
 const issues=[];
 if(!isoDate(doc.date))issues.push('Original document date');
 if(schemas[doc.module]?.party&&!String(doc.party||'').trim())issues.push('Original party');
 if(doc.legacy)issues.push('Verify original item details and amounts');
 if(!doc.lines?.length)issues.push('Product lines');
 else if(doc.lines.some(l=>!String(l.code||l.description||'').trim()||!Number.isFinite(Number(l.quantity))||Number(l.quantity)<=0))issues.push('Original product and quantity details');
 if(['Sales Invoice','Sales Orders','Sales Quotations','Purchase Orders','Purchase','Service Invoice'].includes(doc.module)&&(!Number.isFinite(Number(doc.total))||Number(doc.total)<=0))issues.push('Confirm original amount');
 if(doc.module==='Sales Invoice'){
  if(!String(doc.header?.['Currency Type']||'').trim())issues.push('Invoice currency');
  const due=isoDate(doc.header?.['Due Date']);
  if(!due)issues.push('Invoice due date');
  else if(isoDate(doc.date)&&due<isoDate(doc.date))issues.push('Due date precedes invoice date');
 }
 return issues;
}
