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
  'Route Cards': ['WO No', 'Completed Qty', 'Work Order', 'Qty'],
  'Production Output': ['WO No', 'Good Qty', 'Work Order', 'Qty'],
  'Outward QC': ['Output No', 'Qty', 'Production Output', 'Good Qty'],
  'Inward QC': ['GRN No', 'Qty', 'GRN', 'Received Qty'],
  'Delivery Challan': ['SO No', 'Qty', 'Sales Orders', 'Qty'],
  'Job Work Return DC': ['Inward No', 'Qty', 'Job Work Inward', 'Qty'],
  'Outsource Receipt': ['Issue DC', 'Received Qty', 'Outsource Issue DC', 'Qty']
};
/** Lookup returns a source record object, or null if it has not been loaded. */
export function validateConnectedRecord(title, form, lookup, otherRows=[]) {
  for (const key of ['Qty','Received Qty','Good Qty','Reject Qty','Completed Qty','Accepted Qty','Rejected Qty','Amount','Taxable Amount']) {
    if (!(key in form) || String(form[key] ?? '').trim() === '') continue;
    const value = numberValue(form[key]);
    if (value === null || value < 0) return `${key} must be a non-negative number.`;
  }
  if (title === 'Production Output') {
    const good=numberValue(form['Good Qty']), rejected=numberValue(form['Reject Qty']);
    const work=lookup('Work Order','WO No',form['WO No']);
    const ordered=numberValue(work?.Qty);
    if (ordered !== null && good !== null && rejected !== null && good + rejected > ordered + 1e-8) return 'Good Qty + Reject Qty cannot exceed the work order quantity.';
  }
  if (title === 'Inward Quality') {
    const accepted=numberValue(form['Accepted Qty']), rejected=numberValue(form['Rejected Qty']);
    const grn=lookup('GRN','GRN No',form['GRN No']);
    const received=numberValue(grn?.['Received Qty']);
    if (received!==null && accepted!==null && rejected!==null && accepted+rejected>received+1e-8) return 'Accepted Qty + Rejected Qty cannot exceed GRN received quantity.';
  }
  if (quantityPairs[title]) {
    const [sourceKey,qtyKey,sourceTitle,limitKey]=quantityPairs[title];
    const reference=form[sourceKey];
    if (reference && reference!=='-') {
      const related=lookup(sourceTitle,sourceTitle==='Work Order'?'WO No':sourceTitle==='Production Output'?'Output No':sourceTitle==='Sales Orders'?'SO No':sourceTitle==='GRN'?'GRN No':sourceTitle==='Job Work Inward'?'Inward No':'DC No',reference);
      const actual=numberValue(form[qtyKey]), limit=numberValue(related?.[limitKey]);
      if (limit!==null && actual!==null && actual>limit+1e-8) return `${qtyKey} cannot exceed the linked ${sourceTitle} ${limitKey} (${limit}).`;
    }
  }
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
          if (normalizeReference(row?.[2])!==normalizeReference(invoice) || normalizeReference(row?.[0])===normalizeReference(form['Payment No']??form['Receipt No'])) return sum;
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
    if(indent){data.Item ??= indent.Item;data.Qty ??= indent.Qty;data.Vendor ??= indent.Vendor;}
  }
  if(title==='Sales Quotations' && source.Enquiry){
    const enquiry=lookup('Sales Enquiries','Enquiry No',source.Enquiry);
    if(enquiry){data.Product ??= enquiry.Product;data.Qty ??= enquiry.Qty;data['Expected Delivery'] ??= enquiry['Expected Delivery'];}
  }
  if(title==='Outward QC' && source['Output No']){
    const output=lookup('Production Output','Output No',source['Output No']);
    if(output) data['WO No'] ??= output['WO No'];
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
