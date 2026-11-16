/** Data-only safeguards for connected ERP documents. No UI or database schema changes. */
export const normalizeReference = value => String(value ?? '').trim().toLocaleLowerCase('en');
export const numberValue = value => {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  const normalized = String(value).replaceAll(',', '').replace(/^\s*[₹$]\s*/, '').trim();
  if (!/^-?\d+(?:\.\d+)?$/.test(normalized)) return null;
  const number = Number(normalized);
  return Number.isFinite(number) ? number : null;
};
export function findRecord(rows, columns, column, reference) {
  const index = columns.indexOf(column);
  if (index < 0 || !normalizeReference(reference)) return null;
  return rows.find(row => Array.isArray(row) && normalizeReference(row[index]) === normalizeReference(reference)) || null;
}
export function recordToObject(columns, row) {
  return Object.fromEntries(columns.map((name, index) => [name, row?.[index] ?? '']));
}
const quantityPairs = {
  'Route Cards': ['WO No', ['Completed Qty'], 'Work Order', 'WO No', 'Qty'],
  'Production Output': ['WO No', ['Good Qty', 'Reject Qty'], 'Work Order', 'WO No', 'Qty'],
  'Outward QC': ['Output No', ['Qty'], 'Production Output', 'Output No', 'Good Qty'],
  'Inward QC': ['GRN No', ['Qty'], 'GRN', 'GRN No', 'Received Qty'],
  'Inward Quality': ['GRN No', ['Accepted Qty', 'Rejected Qty'], 'GRN', 'GRN No', 'Received Qty'],
  'Delivery Challan': ['SO No', ['Qty'], 'Sales Orders', 'SO No', 'Qty'],
  'Job Work Return DC': ['Inward No', ['Qty'], 'Job Work Inward', 'Inward No', 'Qty'],
  'Outsource Receipt': ['Issue DC', ['Received Qty'], 'Outsource Issue DC', 'DC No', 'Qty'],
};

function validateLinkedQuantity(title, form, lookup, otherRows, columns, originalReference) {
  const rule=quantityPairs[title];
  if(!rule) return '';
  const [link, quantities, source, sourceId, limitField]=rule;
  const reference=normalizeReference(form[link]);
  if(!reference||reference==='-') return '';
  const limit=numberValue(lookup(source,sourceId,form[link])?.[limitField]);
  const entries=quantities.map(field=>numberValue(form[field]));
  if(limit===null||entries.some(value=>value===null)) return '';
  const quantity=entries.reduce((total,value)=>total+value,0);
  if(quantity>limit+1e-8) return `${quantities.join(' + ')} cannot exceed the linked ${source} ${limitField} (${limit}).`;
  if(!columns.length) return '';
  const statusIndex=columns.findIndex(field=>/^(status|stage|decision|qc status)$/i.test(field));
  const linkIndex=columns.indexOf(link);
  const indexes=quantities.map(field=>columns.indexOf(field));
  // Route cards represent operations, each of which can process the full order.
  if(title==='Route Cards'||/^(rejected|cancelled|void)$/i.test(form[columns[statusIndex]]||'')) return '';
  const used=otherRows.reduce((total,row)=>{
    if(normalizeReference(row?.[0])===normalizeReference(originalReference ?? form[columns[0]]) ||
       normalizeReference(row?.[linkIndex])!==reference ||
       /^(rejected|cancelled|void)$/i.test(row?.[statusIndex]||'')) return total;
    return total+indexes.reduce((sum,index)=>sum+(numberValue(row?.[index])??0),0);
  },0);
  return used+quantity>limit+1e-8
    ? `${quantities.join(' + ')} exceeds the remaining quantity for ${source} ${form[link]} (${Math.max(0,limit-used)}).`
    : '';
}

const upstreamReferences = {
  'Work Order': ['SO No','Sales Orders','SO No'],
  'Material Request': ['Work Order','Work Order','WO No'],
  'Material Issue': ['Work Order','Work Order','WO No'],
  'Route Cards': ['WO No','Work Order','WO No'],
  'Production Output': ['WO No','Work Order','WO No'],
  'Outward QC': ['Output No','Production Output','Output No'],
  'Job Work Return DC': ['Inward No','Job Work Inward','Inward No'],
  'Outsource Receipt': ['Issue DC','Outsource Issue DC','DC No'],
};

const rejectionStages = {
  'GRN':['Awaiting QC'],
  'Inward QC':['Pending'],
  'Outward QC':['Pending'],
  'In-process QC':['In Inspection'],
  'Job Work QC':['In Inspection'],
  'Sales Quotations':['Approval Pending','Sent']
};

export function canRejectProductionDocument(title,status) {
  return rejectionStages[title]?.includes(status)??false;
}

export function nextProductionStatus(statuses,status) {
  const index=statuses?.indexOf(status)??-1;
  const next=index<0?undefined:statuses[index+1];
  return next==='Rejected'?undefined:next;
}

export function receiptPostingStatus(form,invoice,rows) {
  const invoiceTotal=numberValue(invoice?.Amount);
  const amount=numberValue(form.Amount);
  if(invoiceTotal===null||amount===null) return null;
  const total=rows.reduce((posted,row)=>{
    if(!['Part Paid','Settled'].includes(row?.[5])||
      normalizeReference(row?.[0])===normalizeReference(form['Receipt No'])||
      normalizeReference(row?.[2])!==normalizeReference(form.Invoice)) return posted;
    return posted+(numberValue(row?.[4])??0);
  },amount);
  return total>=invoiceTotal-0.009?'Settled':'Part Paid';
}

export function validateProductionProgress(title, form, lookup) {
  if(title==='GRN'&&form['QC Status']==='Accepted'){
    const inspection=lookup('Inward QC','GRN No',form['GRN No']);
    if(inspection?.Status!=='Passed')return 'Pass Inward QC before accepting this GRN into stock.';
    if(numberValue(inspection.Qty)!==numberValue(form['Received Qty'])){
      return 'The passed Inward QC quantity must match the GRN received quantity before accepting stock.';
    }
  }
  if(title==='Customer Payments') {
    const invoice=lookup('Sales Invoice','Invoice No',form.Invoice);
    if(!invoice||String(invoice.Status).toUpperCase()!=='APPROVED') {
      return 'Select an approved Sales Invoice before posting the receipt.';
    }
    if(!(numberValue(form.Amount)>0))return 'Receipt Amount must be greater than zero before posting.';
  }
  const rule=upstreamReferences[title];
  if(rule) {
    const [field,page,key]=rule;
    if(!lookup(page,key,form[field])) return `Select a saved ${page} for ${field} before advancing.`;
  }
  if(title==='Route Cards'&&form.Status==='Completed'&&!(numberValue(form['Completed Qty'])>0)){
    return 'Completed Qty must be greater than zero before completing the route card.';
  }
  if(title==='Production Output'&&!(numberValue(form['Good Qty'])>0||numberValue(form['Reject Qty'])>0)){
    return 'Record the good or rejected quantity before advancing Production Output.';
  }
  return '';
}

/** Lookup returns a source record object, or null if it has not been loaded. */
export function validateConnectedRecord(title, form, lookup, otherRows=[], columns=[], originalReference) {
  for (const key of ['Qty','Received Qty','Good Qty','Reject Qty','Completed Qty','Accepted Qty','Rejected Qty','Amount','Taxable Amount']) {
    if (!(key in form) || String(form[key] ?? '').trim() === '') continue;
    const value = numberValue(form[key]);
    if (value === null || value < 0) return `${key} must be a non-negative number.`;
  }
  const quantityError=validateLinkedQuantity(title,form,lookup,otherRows,columns,originalReference);
  if(quantityError)return quantityError;
  if (title === 'Customer Payments' || title === 'Vendor Payments') {
    const invoice=form.Invoice;
    if (invoice && invoice!=='-') {
      const sourceTitle=title==='Vendor Payments'?'Purchase':'Sales Invoice';
      const sourceField=title==='Vendor Payments'?'Invoice No':'Invoice No';
      const document=lookup(sourceTitle,sourceField,invoice);
      const invoiceAmount=numberValue(document?.Amount??document?.['Taxable Amount']);
      const amount=numberValue(form.Amount);
      if (invoiceAmount!==null && amount!==null) {
        const paid=otherRows.reduce((sum,row)=>{
          if (normalizeReference(row?.[2])!==normalizeReference(invoice) || normalizeReference(row?.[0])===normalizeReference(originalReference??form['Payment No']??form['Receipt No'])) return sum;
          if (String(row?.[5]).toLowerCase().includes('reject')) return sum;
          return sum + (numberValue(row?.[4])??0);
        },0);
        if (paid + amount > invoiceAmount + 0.009) return `Payment exceeds invoice balance. Available: ${(Math.max(0,invoiceAmount-paid)).toFixed(2)}.`;
      }
    }
  }
  return '';
}
/** Reconcile supplied values, never create imaginary fields when the source has none. */
export function resolveWorkflowContext(title, source, lookup, links=[]) {
  const data={...source};
  if(title==='Purchase Orders' && source['PO No']){
    const link=links.find(item=>item.to==='Purchase Orders'&&normalizeReference(item.created)===normalizeReference(source['PO No']));
    const indent=link&&lookup('Indent To Order','Indent No',link.reference);
    if(indent){data.Item ||= indent.Item;data.Qty ||= indent.Qty;data.Vendor ||= indent.Vendor;}
  }
  if(title==='Sales Quotations' && source.Enquiry){
    const enquiry=lookup('Sales Enquiries','Enquiry No',source.Enquiry);
    if(enquiry){data.Product ||= enquiry.Product;data.Qty ||= enquiry.Qty;data['Expected Delivery'] ||= enquiry['Expected Delivery'];}
  }
  if(title==='Outward QC' && source['Output No']){
    const output=lookup('Production Output','Output No',source['Output No']);
    const work=output&&lookup('Work Order','WO No',output['WO No']);
    const order=work&&lookup('Sales Orders','SO No',work['SO No']);
    if(output)data['WO No'] ??= output['WO No'];
    if(work)data['SO No'] ??= work['SO No'];
    if(order)data.Customer ??= order.Customer;
  }
  if(title==='Delivery Challan' && source['Output No']){
    const output=lookup('Production Output','Output No',source['Output No']);
    const work=output&&lookup('Work Order','WO No',output['WO No']);
    const order=work&&lookup('Sales Orders','SO No',work['SO No']);
    if(output){data.Product ??= output.Product;data['WO No'] ??= output['WO No'];}
    if(work)data['SO No'] ??= work['SO No'];
    if(order){data.Customer ??= order.Customer;data['SO No'] ??= order['SO No'];}
  }
  if(title==='Inward QC' && source['GRN No']){
    const grn=lookup('GRN','GRN No',source['GRN No']);
    if(grn){data.Vendor ??= grn.Vendor;data['PO No'] ??= grn['PO No'];data.Item ??= grn.Item;}
  }
  return data;
}
