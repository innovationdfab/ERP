import {nextStages} from './process-schema.js';
export const roundMoney=n=>Math.round((n+Number.EPSILON)*100)/100;
const number=v=>Number(v||0);
export function lineAmounts(line){
 const base=roundMoney(number(line.quantity)*number(line.rate));
 const discount=roundMoney(base*number(line.discount)/100);
 const taxable=roundMoney(base-discount);
 const cgst=roundMoney(taxable*number(line.cgst)/100),sgst=roundMoney(taxable*number(line.sgst)/100),igst=roundMoney(taxable*number(line.igst)/100);
 return {base,discount,taxable,cgst,sgst,igst,gross:roundMoney(taxable+cgst+sgst+igst)};
}
export function documentAmounts(doc){
 const result={taxable:0,discount:0,cgst:0,sgst:0,igst:0,gross:0};
 for(const line of doc.lines||[]){const a=lineAmounts(line);for(const key of Object.keys(result))result[key]+=a[key];}
 for(const charge of doc.charges||[]){const a=lineAmounts({...charge,quantity:1,rate:charge.amount,discount:0});for(const key of Object.keys(result))result[key]+=a[key];}
 for(const key of Object.keys(result))result[key]=roundMoney(result[key]);
 result.gross=roundMoney(result.gross+number(doc.adjustment));
 return result;
}
export function validateDocument(doc,{draft=false}={}){
 if(!doc.date||!/^\d{4}-\d{2}-\d{2}$/.test(doc.date)||!Number.isFinite(Date.parse(doc.date+'T12:00:00Z'))||new Date(doc.date+'T12:00:00Z').toISOString().slice(0,10)!==doc.date)return 'Enter a valid document date.';
 if(!doc.party?.trim()&&!['Rejection Note','Route Cards'].includes(doc.module))return 'Select the customer, prospect, vendor or supplier.';
 if(!draft&&(!doc.assignment?.user?.trim()||!doc.assignment?.department||!doc.assignment?.due))return 'Assign the next task to a user and department with a target date.';
 if(!draft&&doc.assignment.due<doc.date)return 'Target date cannot be before the document date.';
 if(!draft){const required={'Sales Orders':['Customer PO Dt.','C Number','A Number'],'GRN':['Supplier Invoice No.','Supplier Invoice Dt.','PO Ref. Dt.','Work Order No'],'Proforma Invoice':['Advance Payment Amount'],'Inward Quality Rejection':['Supplier Invoice No.','Supplier Invoice Dt.']};for(const label of required[doc.module]||[])if(!String(doc.header?.[label]??'').trim())return `${label} is required before release.`;}
 if(!doc.lines?.length)return 'Add at least one product line.';
 for(const [i,line]of doc.lines.entries()){
  if(!(line.code?.trim()||line.description?.trim()))return `Line ${i+1}: enter a product or description.`;
  if(!Number.isFinite(number(line.quantity))||number(line.quantity)<=0)return `Line ${i+1}: quantity must be greater than zero.`;
  if(!Number.isFinite(number(line.rate))||number(line.rate)<0)return `Line ${i+1}: rate must be non-negative.`;
  for(const field of ['discount','cgst','sgst','igst'])if(!Number.isFinite(number(line[field]))||number(line[field])<0||number(line[field])>100)return `Line ${i+1}: ${field} must be between 0 and 100.`;
  if(number(line.igst)>0&&(number(line.cgst)>0||number(line.sgst)>0))return `Line ${i+1}: use either CGST/SGST or IGST.`;
 }
 for(const charge of doc.charges||[])if(!charge.description?.trim()||!Number.isFinite(number(charge.amount))||number(charge.amount)<0||['cgst','sgst','igst'].some(k=>!Number.isFinite(number(charge[k]))||number(charge[k])<0||number(charge[k])>100)||(number(charge.igst)>0&&(number(charge.cgst)>0||number(charge.sgst)>0)))return 'Enter a valid charge description, amount and tax split.';
 if(!Number.isFinite(number(doc.adjustment)))return 'Enter a valid adjustment.';
 if(documentAmounts(doc).gross<0)return 'Net amount cannot be negative.';
 if(!draft&&['Inward QC','Inward Quality','Outward QC'].includes(doc.module)){
  const qty=doc.lines.reduce((sum,l)=>sum+number(l.quantity),0);
  if(!doc.inspection?.inspector?.trim())return 'Enter the inspector.';
  if(!['Passed','Rejected'].includes(doc.inspection.result))return 'Record a passed or rejected inspection result.';
  if(!Number.isFinite(number(doc.inspection.accepted))||!Number.isFinite(number(doc.inspection.rejected))||number(doc.inspection.accepted)<0||number(doc.inspection.rejected)<0||Math.abs(number(doc.inspection.accepted)+number(doc.inspection.rejected)-qty)>0.000001)return 'Accepted plus rejected quantity must equal inspected quantity.';
  if(doc.inspection.result==='Passed'&&number(doc.inspection.rejected)>0)return 'A passed inspection cannot include rejected quantity. Split the accepted lot first.';
 }
 if(!draft&&doc.module==='Route Cards'){
  if(!doc.operations?.length)return 'Add at least one route operation.';
  const qty=doc.lines.reduce((sum,l)=>sum+number(l.quantity),0);
  if(doc.operations.some(o=>!o.process?.trim()||!Number.isFinite(number(o.quantity))||number(o.quantity)<0||number(o.quantity)>qty))return 'Every operation needs a process and valid completed quantity within the order quantity.';
 }
 return '';
}
export function canForward(doc,target){
 if(!nextStages(doc).includes(target))return 'This is not a configured next stage.';
 if(!['APPROVED','RELEASED','PASSED','COMPLETED','DISPATCHED','DELIVERED'].includes(String(doc.status).toUpperCase()))return 'Approve or release this document before creating the next task.';
 if(['Inward QC','Inward Quality','Outward QC'].includes(doc.module)&&doc.inspection?.result!=='Passed')return 'The inspection must pass before the next stage.';
 if(doc.module==='Route Cards'&&doc.operations?.some(o=>o.status!=='Completed'||(o.qcRequired&&o.qcStatus!=='Passed')))return 'Complete all operations and their required QC checks first.';
 if(doc.module==='Route Cards'&&doc.operations?.some(o=>number(o.quantity)<doc.lines.reduce((s,l)=>s+number(l.quantity),0)))return 'Operation quantities must cover the full order quantity.';
 return '';
}
export function paymentBalance(total,payments){return roundMoney(number(total)-payments.reduce((sum,p)=>sum+number(p.amount)+number(p.tds)+number(p.ld),0));}
export function validatePayment(payment,balance){
 for(const key of ['amount','tds','ld'])if(!Number.isFinite(number(payment[key]))||number(payment[key])<0)return 'Payment, TDS and LD must be non-negative numbers.';
 const allocation=roundMoney(number(payment.amount)+number(payment.tds)+number(payment.ld));
 if(allocation<=0)return 'Enter a payment or deduction amount.';
 if(allocation>roundMoney(balance))return 'Payment and deductions exceed the outstanding balance.';
 if(!payment.date)return 'Payment date is required.';
 if(!payment.type)return 'Select a payment type.';
 if(payment.type!=='Cash'&&!payment.reference?.trim())return 'Payment reference is required.';
 return '';
}
export function projectRow(doc,columns,index=0){
 const total=doc.total??documentAmounts(doc).gross,qty=(doc.lines||[]).reduce((sum,l)=>sum+number(l.quantity),0),line=doc.lines?.[0]||{};
 if(doc.module==='Sales Invoice')return [String(index+1),doc.number,doc.date,doc.party,doc.header['Buyer PO No.']||'-',doc.header['Project Name']||'-',doc.status,String(total),'NOT CONNECTED','',JSON.stringify(doc.lines)];
 return columns.map((col,i)=>{
  if(i===0)return doc.number;
  if(/status|stage|decision/i.test(col))return doc.status;
  if(/^(customer|vendor|supplier)$/i.test(col))return doc.party;
  if(/^taxable amount$/i.test(col))return String(documentAmounts(doc).taxable);
  if(/amount|value/i.test(col))return String(total);
  if(/qty|quantity/i.test(col))return /reject/i.test(col)?String(doc.inspection?.rejected||0):String(qty);
  if(/^(item|product|material)$/i.test(col))return line.code||line.description||'-';
  if(/^(date|PO Date|Invoice Date)$/i.test(col))return doc.date;
  const aliases={'Customer PO':'PO Number','Delivery':'Expected Delivery Date.','Expected Delivery':'Target Date','Enquiry':'Enq Ref. No.','SO No':'SO Ref No','Work Order':'WO No','Vehicle':'Vehicle No.','GRN No':'GRN No','Output No':'Output No','Invoice':'Invoice'};
  return doc.header[col]||doc.header[aliases[col]]||doc.references?.[col]||(/inspector/i.test(col)?doc.inspection?.inspector:'')||'-';
 });
}
