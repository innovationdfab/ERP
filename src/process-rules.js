import {imantraTransactions} from './imantra-integration.js';
import {nextStages,schemas,QUALITY_MODULES} from './process-schema.js';
export const roundMoney=n=>Math.round((n+Number.EPSILON)*100)/100;
const number=v=>Number(v||0);
const validDate=value=>!!value&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T12:00:00Z'))&&new Date(value+'T12:00:00Z').toISOString().slice(0,10)===value;
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
 if(!validDate(doc.date))return 'Enter a valid document date.';
 if(!doc.party?.trim()&&Boolean(schemas[doc.module]?.party))return 'Select the customer, prospect, vendor or supplier.';
 if(!draft&&(!doc.assignment?.user?.trim()||!doc.assignment?.department||!doc.assignment?.due))return 'Assign the next task to a user and department with a target date.';
 if(!draft&&doc.assignment.due<doc.date)return 'Target date cannot be before the document date.';
 if(!draft){const required={'Sales Orders':['Customer PO Dt.','C Number','A Number'],'GRN':['Supplier Invoice No.','Supplier Invoice Dt.','PO Ref. Dt.','Work Order No'],'Proforma Invoice':['Advance Payment Amount'],'Inward Quality Rejection':['Supplier Invoice No.','Supplier Invoice Dt.']};for(const label of required[doc.module]||[])if(!String(doc.header?.[label]??'').trim())return `${label} is required before release.`;}
 if(doc.module==='Sales Invoice'&&doc.header?.['Credit Days']!==undefined&&doc.header['Credit Days']!==''&&(!/^\d+$/.test(doc.header['Credit Days'])||Number(doc.header['Credit Days'])>3650))return 'Credit Days must be a whole number from 0 to 3650.';
 if(doc.module==='Sales Invoice'&&!draft&&(!validDate(doc.header?.['Due Date'])||doc.header['Due Date']<doc.date))return 'Enter an invoice due date on or after its document date.';
 if(!doc.lines?.length)return 'Add at least one product line.';
 for(const [i,line]of doc.lines.entries()){
  if(!(line.code?.trim()||line.description?.trim()))return `Line ${i+1}: enter a product or description.`;
  if(!Number.isFinite(number(line.quantity))||number(line.quantity)<=0)return `Line ${i+1}: quantity must be greater than zero.`;
  if(!Number.isFinite(number(line.rate))||number(line.rate)<0)return `Line ${i+1}: rate must be non-negative.`;
  for(const field of ['discount','cgst','sgst','igst'])if(!Number.isFinite(number(line[field]))||number(line[field])<0||number(line[field])>100)return `Line ${i+1}: ${field} must be between 0 and 100.`;
  if(number(line.cgst)+number(line.sgst)>100)return `Line ${i+1}: combined CGST/SGST cannot exceed 100%.`;
  if(!Number.isSafeInteger(Math.round(number(line.quantity)*number(line.rate)*100)))return `Line ${i+1}: amount is too large.`;
  if(number(line.igst)>0&&(number(line.cgst)>0||number(line.sgst)>0))return `Line ${i+1}: use either CGST/SGST or IGST.`;
 }
 for(const charge of doc.charges||[])if(!charge.description?.trim()||!Number.isFinite(number(charge.amount))||number(charge.amount)<0||['cgst','sgst','igst'].some(k=>!Number.isFinite(number(charge[k]))||number(charge[k])<0||number(charge[k])>100)||(number(charge.igst)>0&&(number(charge.cgst)>0||number(charge.sgst)>0)))return 'Enter a valid charge description, amount and tax split.';
 if(!Number.isFinite(number(doc.adjustment)))return 'Enter a valid adjustment.';
 if(documentAmounts(doc).gross<0)return 'Net amount cannot be negative.';
 if(!draft&&QUALITY_MODULES.includes(doc.module)){
  const qty=doc.lines.reduce((sum,l)=>sum+number(l.quantity),0);
  if(!doc.inspection?.inspector?.trim())return 'Enter the inspector.';
  if(!['Passed','Rejected'].includes(doc.inspection.result))return 'Record a passed or rejected inspection result.';
  if(!Number.isFinite(number(doc.inspection.accepted))||!Number.isFinite(number(doc.inspection.rejected))||number(doc.inspection.accepted)<0||number(doc.inspection.rejected)<0||Math.abs(number(doc.inspection.accepted)+number(doc.inspection.rejected)-qty)>0.000001)return 'Accepted plus rejected quantity must equal inspected quantity.';
  if(doc.inspection.result==='Passed'&&number(doc.inspection.rejected)>0)return 'A passed inspection cannot include rejected quantity. Split the accepted lot first.';
 }
 if(!draft&&QUALITY_MODULES.includes(doc.module)){
  for(const [i,c] of (doc.inspection.characteristics||[]).entries()){
   if(!c.name?.trim()||!c.unit?.trim()||c.actual===''||!Number.isFinite(Number(c.actual))||
     c.min!==''&&!Number.isFinite(Number(c.min))||c.max!==''&&!Number.isFinite(Number(c.max))||
     c.min!==''&&c.max!==''&&Number(c.min)>Number(c.max))return `Inspection characteristic ${i+1}: enter a name, unit and valid limits/measurement.`;
   if(doc.inspection.result==='Passed'&&(c.min!==''&&Number(c.actual)<Number(c.min)||c.max!==''&&Number(c.actual)>Number(c.max)))return `Inspection characteristic ${i+1} is outside its acceptance limits.`;
  }
 }
 if(!draft&&doc.legacy&&!doc.legacyReviewed)return 'Verify the original item details and confirm legacy reconciliation before release.';
 if(!draft&&imantraTransactions[doc.module]){
  for(const field of imantraTransactions[doc.module].fields.slice(1)){
   if(/^(Item|Product|Material|Qty|Amount|Value|Quantity Change|Customer|Vendor|Supplier|Good Qty|Consumed Qty)$/.test(field))continue;
   if(/^(Available Qty|Reject Qty)$/.test(field)&&!doc.header[field])continue;
   if(String(doc.header[field]??'').trim()==='')return `${field} is required before release.`;
  }
 }
 if(!draft&&doc.module==='Route Cards'){
  if(!doc.operations?.length)return 'Add at least one route operation.';
  const qty=doc.lines.reduce((sum,l)=>sum+number(l.quantity),0);
  if(doc.operations.some(o=>!o.process?.trim()||!Number.isFinite(number(o.quantity))||number(o.quantity)<0||number(o.quantity)>qty))return 'Every operation needs a process and valid completed quantity within the order quantity.';
  if(doc.operations.some(o=>o.type==='Outsource'?!o.vendor?.trim():!o.machine?.trim()))return 'Assign a machine for in-house operations and a vendor for outsourced operations.';
 }
 return '';
}
export function canForward(doc,target){
 if(doc.workflowNext===target&&doc.workflowGates?.length&&!doc.workflowGates.some(s=>String(s).toUpperCase()===doc.status))return 'The published workflow status gate has not been reached.';
 if(!nextStages(doc).includes(target))return 'This is not a configured next stage.';
 if(!['APPROVED','RELEASED','PASSED','ACCEPTED','COMPLETED','DISPATCHED','DELIVERED'].includes(String(doc.status).toUpperCase()))return 'Approve or release this document before creating the next task.';
 if(QUALITY_MODULES.includes(doc.module)&&doc.inspection?.result!=='Passed')return 'The inspection must pass before the next stage.';
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
export function compatibilityStatus(doc){
 const status=String(doc.status||'').toUpperCase();
 const special={GRN:{RELEASED:'Awaiting QC',ACCEPTED:'Accepted'},'Material Issue':{RELEASED:'Issued'},'Opening Stock':{RELEASED:'Posted'},'Excess Stock':{RELEASED:'Adjusted'},'Shortage Stock':{RELEASED:'Adjusted'},'Scrap Entry':{RELEASED:'Disposed'},'Production Output':{RELEASED:'QC Pending',ACCEPTED:'Accepted'},'Work Order':{DRAFT:'Planned'},Purchase:{RELEASED:'Posted'},'Purchase Return':{RELEASED:'Returned'},'Stock Adjustment':{RELEASED:'Posted'},'Return to Store':{RELEASED:'Posted'}};
 const released={'Import Purchase':'Received','Procurement Schedule':'Confirmed','Dispatch Schedule':'Ready','Project Planning':'Active','Job Order':'Issued','Jobwork Material Issue':'Issued','Jobwork Material Receipt':'Accepted','Service Invoice':'Posted','Input to Production':'Issued','Stage Receipt':'Completed','Stage Consumption':'Posted','Excess Issue':'Issued','Dispatch Intimation':'Sent','Material Reserve':'Reserved','Project Order':'Running','Pick Slip':'Confirmed','Put Away':'Completed','Terminate Order':'Closed','Indent To Order':'Open'};
 if(status==='RELEASED'&&released[doc.module])return released[doc.module];
 if(doc.module==='Sales Invoice')return status==='RELEASED'?'APPROVED':status;
 return special[doc.module]?.[status]||({'DRAFT':'Draft','APPROVED':'Approved','APPROVAL PENDING':'Approval Pending','REJECTED':'Rejected','RELEASED':'Released','PASSED':'Passed','ACCEPTED':'Accepted','COMPLETED':'Completed','DISPATCHED':'Dispatched','DELIVERED':'Delivered'}[status]||doc.status);
}
export function projectRow(doc,columns,index=0){
 const total=doc.total??documentAmounts(doc).gross,qty=(doc.lines||[]).reduce((sum,l)=>sum+number(l.quantity),0),line=doc.lines?.[0]||{};
 if(doc.module==='Sales Invoice')return [String(index+1),doc.number,doc.date,doc.party,doc.header['Buyer PO No.']||'-',doc.header['Project Name']||'-',compatibilityStatus(doc),String(total),'NOT CONNECTED','',JSON.stringify(doc.lines)];
 return columns.map((col,i)=>{
  if(i===0)return doc.number;
  if(/status|stage|decision/i.test(col))return compatibilityStatus(doc);
  if(/^(customer|vendor|supplier)$/i.test(col))return doc.party;
  if(/^taxable amount$/i.test(col))return String(documentAmounts(doc).taxable);
  if(/amount|value/i.test(col))return String(total);
  if(doc.module==='Stock Adjustment'&&col==='Quantity Change')return String(qty*(doc.header['Adjustment direction']==='Decrease'?-1:1));
  if(/qty|quantity/i.test(col)&&doc.header[col]!==undefined&&doc.header[col]!=='')return doc.header[col];
  if(/qty|quantity/i.test(col))return /reject/i.test(col)?String(doc.inspection?.rejected||0):String(qty);
  if(/^(item|product|material)$/i.test(col))return line.code||line.description||'-';
  if(/^(date|PO Date|Invoice Date)$/i.test(col))return doc.date;
  const aliases={'Customer PO':'PO Number','Delivery':'Expected Delivery Date.','Expected Delivery':'Target Date','Enquiry':'Enq Ref. No.','PO No':'PO Ref No','SO No':'SO Ref No','Work Order':'WO No','Vehicle':'Vehicle No.','GRN No':'GRN No','Output No':'Output No','Invoice':'Invoice'};
  const referenceModules={'PO No':'Purchase Orders','SO No':'Sales Orders','WO No':'Work Order','Work Order':'Work Order','GRN No':'GRN','Output No':'Production Output','Invoice':'Sales Invoice'};
  return doc.header[col]||doc.header[aliases[col]]||doc.references?.[referenceModules[col]]||doc.references?.[col]||(/inspector/i.test(col)?doc.inspection?.inspector:'')||'-';
 });
}

/** Physical production documents require a released, traceable predecessor. */
export function validateReleaseChain(doc,documents){
 if(['DRAFT','APPROVAL PENDING','REJECTED'].includes(doc.status))return '';
 const find=module=>documents.find(d=>d.module===module&&d.number===(doc.source?.module===module?doc.source.number:doc.references?.[module]));
 const passed=module=>find(module)?.status==='PASSED'&&find(module)?.inspection?.result==='Passed';
 if(['Inward QC','Inward Quality','Outward QC','In-process QC','Job Work QC','Production Output','Material Issue','Outsource Receipt','Outsource Issue DC','GRN'].includes(doc.module)&&!doc.source)return 'Fetch the released source document before release.';
 if((doc.module==='Work Order'||doc.module==='Sales Orders'&&doc.flow==='labour')&&!passed('Inward QC'))return 'Fetch passed inward QC before releasing the manufacturing work order.';
 if(['Delivery Challan','Job Work Return DC'].includes(doc.module)&&!passed('Outward QC'))return 'Fetch passed outward QC before releasing the delivery challan.';
 if(doc.module==='Purchase'&&find('GRN')?.status!=='ACCEPTED')return 'Fetch an accepted GRN after inward QC before posting the purchase invoice.';
 if(doc.module==='Sales Invoice'){
  const dispatch=find('Delivery Challan')||find('Job Work Return DC');
  if(!dispatch||!['APPROVED','RELEASED','DISPATCHED','DELIVERED'].includes(dispatch.status))return 'Fetch a released delivery or job-work return challan before releasing the invoice.';
 }
 if(doc.module==='Production Output'){
  const route=find('Route Cards');
  if(!route||canForward(route,'Production Output'))return 'Complete the route card and its operation QC before recording production output.';
 }
 return '';
}
