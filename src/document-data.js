import { calculateInvoice } from './invoice-calculations.js';
import { detailsFromRow, invoiceHeaderKeys } from './reference-forms.js';
import { normalizeReference, numberValue, recordToObject } from './workflow-integrity.js';

export const invoiceColumns=['#','Invoice No','Date','Customer','Buyer PO No.','Project Name','Status','Amount','Sync','Remarks'];
export const hasDocumentValue=value=>value!==undefined&&value!==null&&String(value).trim()!==''&&value!=='-';

export function describeDocument(module,columns,row,invoiceDetail) {
  const invoice=module==='Sales Invoice';
  const extra=invoice?invoiceDetail:detailsFromRow(columns,row);
  const fields={...(invoice?extra?.form:extra?.header)};
  delete fields.fetchedFrom;
  if(invoice) {
    for(const [label,key] of Object.entries(invoiceHeaderKeys)) {
      if(hasDocumentValue(fields[key]))fields[label]=fields[key];
    }
  }
  for(const [key,value] of Object.entries(recordToObject(columns,row))) {
    if(hasDocumentValue(value)||!Object.hasOwn(fields,key))fields[key]=value;
  }
  let lines=extra?.lines;
  if(invoice&&!Array.isArray(lines)&&typeof row?.[10]==='string') {
    try {lines=JSON.parse(row[10]);}catch { /* Legacy summary without line data. */ }
  }
  lines=Array.isArray(lines)?lines.filter(line=>line&&typeof line==='object'):[];
  if(lines.length===1) {
    const [line]=lines;
    fields.Product=line.description||line.code;
    fields.Qty=line.quantity;
    fields.UOM=line.uom;
  }
  return {number:String(row?.[invoice?1:0]??''),fields,lines,fetchedFrom:extra?.fetchedFrom};
}

export function fetchConflict(reference,form,record) {
  return reference&&hasDocumentValue(form[reference])&&normalizeReference(form[reference])!==normalizeReference(record.number)
    ? `Clear ${reference} before fetching a different source document.`
    : '';
}

export function documentReportRows(name,columns,readDocuments,readRows,canRead=()=>true) {
  const project=fields=>columns.map(key=>hasDocumentValue(fields[key])?fields[key]:'-');
  if(name==='Sales Register'||name==='Sales Register Headerwise') {
    return readDocuments('Sales Invoice').flatMap(({fields,lines})=>{
      const header={...fields,'Invoice Date':fields.Date,'PO Number':fields['Buyer PO No.'],
        Project:fields['Project Name'],'Net Amount':fields.Amount,'E-Invoice Status':fields.Sync};
      const detail=readRows('dfab-invoice-details-v1',{})?.[fields['Invoice No']];
      let totals;
      if(detail)try {totals=calculateInvoice(lines,String(detail.form?.taxRate??''),detail.charges,detail.expenses);}catch { /* Leave unavailable amounts blank. */ }
      // Confirm calculated figures agree with the saved invoice before reporting them.
      if(totals&&Math.abs(totals.total-(numberValue(fields.Amount)??Infinity))>0.009)totals=undefined;
      if(name==='Sales Register Headerwise')return [project({...header,'Taxable Amount':totals?.taxable,
        CGST:totals?.cgst||undefined,SGST:totals?.sgst||undefined,IGST:totals?.igst||undefined})];
      if(!lines.length)return [project(header)];
      return lines.map((line,index)=>project({...header,Product:line.description||line.code,Qty:line.quantity,UOM:line.uom,
        'Taxable Amount':totals?.details[index]?.taxable,'Tax Amount':totals?.details[index]?.tax,
        'Net Amount':totals?.details[index]?.gross}));
    });
  }
  if(name==='Pending Receivables'||name==='Pending Payables') {
    const sales=name==='Pending Receivables';
    const payments=readDocuments(sales?'Customer Payments':'Vendor Payments');
    const paid=new Map();
    for(const {fields} of payments) {
      if(!(sales?['Part Paid','Settled']:['Paid']).includes(fields.Status))continue;
      const key=normalizeReference(fields.Invoice);
      if(key&&key!=='-')paid.set(key,(paid.get(key)??0)+(numberValue(fields.Amount)??0));
    }
    return readDocuments(sales?'Sales Invoice':'Purchase').flatMap(({number,fields})=>{
      if(!(sales?['APPROVED']:['Posted','Paid']).includes(fields.Status))return [];
      const amount=numberValue(fields.Amount??fields['Taxable Amount']);
      if(amount===null)return [];
      const received=paid.get(normalizeReference(number))??0;
      const balance=Math.round((amount-received)*100)/100;
      if(balance<=0)return [];
      return [project({...fields,'Invoice No':number,'Invoice Date':fields['Invoice Date']||fields.Date,
        'Invoice Amount':amount,'Paid Amount':received,'Received Amount':received,'Balance Amount':balance})];
    });
  }
  if(name==='Work Order Register'||name==='Pending Work Order for Production Output'){
    const produced=sumLinkedQuantities(readDocuments('Production Output'),'WO No','Good Qty',['Accepted']);
    return readDocuments('Work Order').flatMap(({number,fields})=>{
      const output=canRead('Production Output')?(produced.get(normalizeReference(number))??0):undefined;
      const ordered=numberValue(fields.Qty);
      const pending=ordered===null||output===undefined?undefined:Math.max(0,ordered-output);
      if(name!=='Work Order Register'&&(!pending||!['Released','Running','QC Pending'].includes(fields.Status)))return [];
      return [project({...fields,'Work Order No':number,'WO Date':fields.Date,'Sales Order No':fields['SO No'],
        'Order Qty':ordered,'Produced Qty':output,'Output Qty':output,'Pending Qty':pending})];
    });
  }
  if(name==='Sales Order Register'||name==='Pending Sales Order for Work Order'){
    const delivered=sumLinkedQuantities(readDocuments('Delivery Challan'),'SO No','Qty',['Delivered']);
    const planned=sumLinkedQuantities(readDocuments('Work Order'),'SO No','Qty',['Planned','Released','Running','QC Pending','Completed']);
    return readDocuments('Sales Orders').flatMap(({number,fields})=>{
      const key=normalizeReference(number);
      const orderQty=numberValue(fields.Qty);
      const deliveredQty=canRead('Delivery Challan')?(delivered.get(key)??0):undefined;
      const workQty=planned.get(key)??0;
      const completed=name==='Sales Order Register'?deliveredQty:workQty;
      const remaining=orderQty===null||completed===undefined?undefined:Math.max(0,orderQty-completed);
      if(name!=='Sales Order Register'&&(!remaining||!['Approved','Production Pending','Production Running'].includes(fields.Status)))return [];
      return [project({...fields,'Sales Order No':number,'SO Date':fields.Date,'Order Qty':orderQty,'Delivered Qty':deliveredQty,
        'Work Order Qty':workQty,'Pending Qty':remaining,'Delivery Date':fields.Delivery})];
    });
  }
  if(name==='Pending Sales Order for Invoice'){
    const invoices=readDocuments('Sales Invoice').filter(({fields})=>fields.Status==='APPROVED');
    const dispatchOrders=new Map(readDocuments('Delivery Challan').map(({number,fields})=>[normalizeReference(number),fields['SO No']]));
    const byOrder=new Map();
    const missingLines=new Set();
    for(const {fields,lines} of invoices){
      const order=normalizeReference(fields.sourceOrder||dispatchOrders.get(normalizeReference(fields.dc)));
      if(!order||order==='-')continue;
      if(!lines.length)missingLines.add(order);
      const existing=byOrder.get(order)||[];
      byOrder.set(order,[...existing,...lines]);
    }
    return readDocuments('Sales Orders').flatMap(({number,fields})=>{
      const ordered=numberValue(fields.Qty);
      if(ordered===null||fields.Status==='Draft')return [];
      const product=normalizeReference(fields.Product);
      const lines=byOrder.get(normalizeReference(number))||[];
      const quantity=lines.filter(line=>product&&(normalizeReference(line.code)===product||normalizeReference(line.description)===product))
        .reduce((sum,line)=>sum+(numberValue(line.quantity)??0),0);
      if(quantity>=ordered)return [];
      const incomplete=missingLines.has(normalizeReference(number));
      return [project({...fields,'Sales Order No':number,'SO Date':fields.Date,'Order Qty':ordered,
        'Invoiced Qty':incomplete?undefined:quantity,'Pending Qty':incomplete?undefined:ordered-quantity,'Delivery Date':fields.Delivery})];
    });
  }
  if(name==='Pending Purchase Order to GRN'||name==='Pending Purchase Indent For GR'){
    const received=sumLinkedQuantities(readDocuments('GRN').map(document=>({...document,
      fields:{...document.fields,Status:document.fields['QC Status']}})),'PO No','Received Qty',['Accepted']);
    return readDocuments('Purchase Orders').flatMap(({number,fields})=>{
      if(!['Approved','Sent','Partially Received'].includes(fields.Status))return [];
      if(name==='Pending Purchase Indent For GR'&&!hasDocumentValue(fields['Indent No']))return [];
      const ordered=numberValue(fields.Qty);
      const qtyReceived=received.get(normalizeReference(number))??0;
      if(ordered===null||ordered<=qtyReceived)return [];
      return [project({...fields,'Order Qty':ordered,'GRN Qty':qtyReceived,'Received Qty':qtyReceived,
        'Pending Qty':ordered-qtyReceived,Product:fields.Item})];
    });
  }
  const mappings={
    'Enquiry Register':['Sales Enquiries',{'Enquiry Date':'Date','Expected Date':'Expected Delivery',Owner:'Managed By'}],
    'Sales Quotation Register':['Sales Quotations',{'Enquiry No':'Enquiry',Value:'Amount','Valid Until':'Quotation Validity'}],
    'Sales Quotation Register Headerwise':['Sales Quotations',{'Enquiry No':'Enquiry',Value:'Amount',Validity:'Quotation Validity','Prepared By':'Managed By'}],
    'Purchase Order Register':['Purchase Orders',{'Product / Service':'Item','Order Qty':'Qty','PO Value':'Amount'}],
    'GRN Register':['GRN',{'GRN Date':'Date','Invoice No':'Supplier Invoice No.',Product:'Item',Status:'QC Status'}],
    'Inward QC Register':['Inward QC',{'IQC No':'QC No',Product:'Item','Inspected Qty':'Qty'}],
    'DC Register':['Delivery Challan',{'DC Date':'Date','Sales Order No':'SO No','Dispatch Qty':'Qty','Vehicle No':'Vehicle'}],
    'DC Register Headerwise':['Delivery Challan',{'DC Date':'Date','Sales Order No':'SO No','Vehicle No':'Vehicle',Transporter:'Transporter Name'}],
    'Purchase Invoice Register':['Purchase',{'Purchase Invoice No':'Invoice No','Vendor Invoice No':'Invoice No.','Tax Amount':'Tax','Net Amount':'Amount'}],
    'Credit Note Register':['Credit Note',{'Invoice No':'Invoice','Net Amount':'Amount'}],
    'Proforma Invoice Register':['Proforma Invoice',{'Sales Order No':'SO No','Net Amount':'Amount'}],
    'Outsource DC Register Headerwise':['Outsource Issue DC',{'Outsource DC No':'DC No','Work Order No':'Work Order','Vehicle No':'Vehicle No'}],
    'Outsource Receipt Register':['Outsource Receipt',{'Receipt Date':'Date','Outsource DC No':'Issue DC'}],
    'Rejection Note Register':['Rejection Note',{'Rejection Note No':'Rejection No','Work Order No':'Work Order','Rejected Qty':'Qty'}],
    'Jobwork Inward Register':['Job Work Inward',{'Jobwork Inward No':'Inward No','Customer DC No':'DC No',Product:'Material'}]
  };
  const definition=mappings[name];
  if(!definition)return null;
  const [module,aliases]=definition;
  return readDocuments(module).map(({fields})=>project({...fields,
    ...Object.fromEntries(Object.entries(aliases).map(([key,source])=>[key,hasDocumentValue(fields[source])?fields[source]:fields[key]]))
  }));
}

function sumLinkedQuantities(documents,reference,quantity,statuses){
  const quantities=new Map();
  for(const {fields} of documents){
    if(!statuses.includes(fields.Status)||!hasDocumentValue(fields[reference]))continue;
    const number=normalizeReference(fields[reference]);
    const qty=numberValue(fields[quantity]);
    if(qty!==null)quantities.set(number,(quantities.get(number)??0)+qty);
  }
  return quantities;
}
