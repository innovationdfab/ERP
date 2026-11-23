/** Labels from the November 2 signed-in ERP review. */
const split = text => text ? text.split('|') : [];
const quality = 'Pipe Drawing No & Rev|TTL Ref No.|Material|WPS Used|Weder Code|Electrode/Filler rod used|Project Name|PO Number|C Number|A Number|Next Task Assigned to|Target Date';
const shipping = 'DC Number|Buyer PO No.|Vehicle No.|Terms of payment|DC date|Buyer Ref Date|Mode of Dispatch|Date Of Supply|Country of Shipment/Destination|E-Way Bill No|E-Way Bill Date|Vendor Code|MGP/Customer DC No|MGP/Customer DC Date|IRN No|Lut No|Ack No|Ack Date|Transporter Name|Project Name|Valid Upto|Kind Attention|Quotation No|Quotation Date|PO Date|Managed By|Scope Of Work|C Number|A Number|Signature Required|Incoterms|Destination|Currency Type';
const raw = {
 'Sales Enquiries':['Prospect','LOCAL','Enquiry Category|Enquiry Remarks|Next Task Assigned to|Enquiry Reference No|Enquiry Reference Date|Target Date|Managed By|Kind Attention|Scope Of Work|Priority'],
 'Sales Quotations':['Prospect','LOCAL','Quotation Category|Quotation Remarks|Enq Ref date.|Enq Ref. No.|Next Task Assigned to|Payment Terms|Mode of Enq.|PO Number|Work Order Number|Project Name|Ref Contact Person|Taxes|Inspection|Delivery Term|Quotation Validity|Lead Time|Managed By|Target Date|Scope Of Work|Priority|Currency Type','Excel Copy'],
 'Sales Orders':['Customer','LOCAL','Order Remarks|Customer PO Dt.|Project Name/Code|PO Number|Expected Delivery Date.|Kind Attention|Managed By|Quotation No|Quotation Date|Next Task Assigned to|Target Date|Scope Of Work|C Number|A Number','Order Copy'],
 'Purchase Orders':['Vendor','PURCHASE ORDER|OTHER','Category|Department|Order Remarks|Invoice No.|Invoice Date|Delivery Need Date|Work Order Number|Project Name|Approved By|Purchased By|Signature Required|Requested By|Indent No|Item|Qty|UOM|Rate','Quotation Document'],
 'Purchase Indents':['Vendor','INDENT','Indent Remarks|Ref Tran No'],
 'GRN':['Vendor','GRN','Category|Department|MRN Remarks|Supplier Invoice No.|Supplier Invoice Dt.|PO Ref No|PO Ref. Dt.|Work Order No','Weighment Slip|Inspection Report'],
 'Work Order':['Customer','WORK ORDER|JOB ORDER','Category|Remarks|SO Ref No|Project Name/Code|PO Number|Managed By|Next Task Assigned to|Target Date|Scope Of Work'],
 'Material Request':['Customer','MATERIAL REQUEST','Remarks|Work Order No.|PO Number'],
 'Material Issue':['Vendor','MATERIAL ISSUE|MATERIAL SCRAP','Departments|Remarks|Work Order No.|Project Name/Code|Sale Order No|PO Number'],
 'Production Output':['Customer','OUTPUT','Remarks|PO Number|Ref Work Order Number|Target Date|Next Task Assigned to'],
 'Outward QC':['Vendor','Outward QC',`${quality}|Stage|Weld Repair Drawing Number|Pipe Welding Drawing Number|Dispatch Date|MPT Test Date|Remarks`],
 'Delivery Challan':['Vendor','DELIVERY CHALLAN','Consignee|Category|Approximate Goods Value|Tran Ref No|PO Number|MGP/Customer DC Number|Project Name|Eway Bill No|Vehicle No.|Transporter Name|Eway Bill Date|Valid Upto|Kind Attention|Remarks|Bill Of Loading/LR-RR No.|MGP/Customer Dc Date|PO Date|Managed By|Scope Of Work|C Number|A Number'],
 'Sales Invoice':['Customer','LOCAL|EXPORT',`Invoice Category|${shipping}`,'Documents Upload'],
 'Purchase':['Vendor','PURCHASE INVOICE','Order Remarks|Invoice No.|Invoice Date|Sale Order Number|Project Name|Approved By|Purchased By|Work Order Number'],
 'Job Work Inward':['Vendor','Job Work Inward','Remarks|PO Number|DC NO.|DC Date.|Approximate Goods Value.|Kind Attention|SUB Vendor|Project Name|C Number|A Number|Next Task Assigned to|Target Date','Attachment'],
 'Job Work Return DC':['Vendor','Job Work Return','Remarks|E-Way Bill No|E-Way Bill Date|Valid Upto|Transporter Name|Vehicle No.|Estimated Goods Value'],
 'Outsource Issue DC':['Vendor','Outsource Issue','Remarks|Our Po No|Due Date|Estimated Value|Transport By|Vehicle No|e-Way Bill No|Project Name|E-Way Bill Date|Valid Upto|Delivery BY'],
 'Outsource Receipt':['Vendor','Outsource Receipt','Remarks|Vendor Invoice Number|Vendor Invoice Basic Value|Vendor Invoice Taxable Value|Vendor DC Number|Vendor DC Date|Invoice Date','Attachment'],
 'Inward Quality':['Supplier','Inward QC',`${quality}|Remarks`],
 'Inward Quality Rejection':['Supplier','Inward Quality Rejection','Remarks|Supplier Invoice No.|Supplier Invoice Dt.'],
 'Rejection Note':['','Rejection Note','Remarks|Ref Process Name|Ref WorkOrder No.|Rejection Type|Rejection Remarks'],
 'Sales Return':['Customer','REGULAR','Consignee'],
 'Proforma Invoice':['Customer','Proforma Invoice','Consignee|Invoice Remarks|Date Of Supply|Project Name|Kind Attention|Quotation No|Quotation Date|Advance Payment Amount|PO Number|Payment Terms'],
 'Credit Note':['Customer','Credit Note','Consignee|Category|DC Number|Buyer PO No.|Vehicle No.|Terms of payment|DC date|Buyer Ref Date|Transportation Mode|Date Of Supply|Place Of Supply|E-Way Bill No|E-Way Bill Date|Vendor Code|Reference DC No|Reference DC Date|IRN No|Tax Payable on Reverse Charge|TAN|Lut No|Ack No|Ack Date|Transporter ID|Transporter Name|Reference Tran No'],
 'Scrap Entry':['Customer','SCRAP','Scrap Category|Scrap Remarks'],
 'Opening Stock':['Vendor','STOCK','Remarks'],
 'Excess Stock':['Vendor','Excess','Remarks'],
 'Shortage Stock':['Vendor','Shortage','Remarks'],
 // These two screens have distinct layouts in iMANTRA; their inspection/operation
 // controls are deliberately separate from the common commercial header.
 'Inward QC':['Supplier','Inward QC','Supplier Invoice No.|Supplier Invoice Dt.|PO Ref No|PO Ref. Dt.|GRN No|Job Inward No|Inspector|Inspection Remarks'],
 'Route Cards':['Customer','Route Card','WO No|Master Route Card No|Revision|Project Name|Managed By']
};
export const referenceForms=Object.fromEntries(Object.entries(raw).map(([name,[party,series,fields,files]])=>[name,{party,series:split(series),fields:split(fields),files:split(files)}]));
export const referenceDefaults={
  'Sales Enquiries':{'Enquiry Category':'DIRECT'},
  'Sales Quotations':{'Quotation Category':'MAIL'},
  'Purchase Orders':{Category:'LOCAL',Department:'STORES'},
  'GRN':{Category:'LOCAL',Department:'Stores'},
  'Work Order':{Category:'JOBWORK'},
  'Delivery Challan':{Category:'SERVICE'}
};
export function referenceOptions(name,label){
 if(label==='Enquiry Category')return ['DIRECT','MAIL','ONLINE','REFERENCE'];
 if(label==='Quotation Category')return ['MAIL'];
 if(label==='Invoice Category')return ['Labour Job','Manufacturing and Supply'];
 if(label==='Departments')return ['Arc / Spot / Stud Weld','Assembly','Bending','Buffing Hardware','Clinching Hardware','Electrical Hardware','Fabrication Hardware','Packing Material','Powder Coating','Raw Material','Sanding Hardware','Sheets','Welding Hardware'];
 if(label==='Priority')return ['Low','Medium','High','Urgent'];
 if(label==='Currency Type')return ['INR','USD','EUR','GBP'];
 if(label==='Category')return name==='Work Order'?['JOBWORK','REGULAR']:name==='Purchase Orders'?['IMPORT','LOCAL']:name==='Delivery Challan'?['SERVICE']:name==='Credit Note'?['EXPORT','LOCAL']:['LOCAL'];
 if(label==='Signature Required')return ['Yes','No'];
 return null;
}
export function referenceInputType(label){
 if(/date|\bdt\.?|valid upto/i.test(label))return 'date';
 if(/amount|goods value|estimated value|invoice basic value|invoice taxable value|^(qty|rate)$/i.test(label))return 'number';
 return /remarks|scope of work/i.test(label)?'textarea':'text';
}

const aliases = {
  'Sales Enquiries': {'Prospect':'Customer'},
  'Sales Quotations': {'Prospect':'Customer','Enq Ref. No.':'Enquiry'},
  'Sales Orders': {'PO Number':'Customer PO','Expected Delivery Date.':'Delivery'},
  'Purchase Orders': {'Delivery Need Date':'Delivery Date'},
  'GRN': {'PO Ref No':'PO No'},
  'Work Order': {'SO Ref No':'SO No'},
  'Material Request': {'Work Order No.':'Work Order'},
  'Material Issue': {'Work Order No.':'Work Order'},
  'Production Output': {'Ref Work Order Number':'WO No'},
  'Delivery Challan': {'Vehicle No.':'Vehicle'},
  'Job Work Inward': {'DC NO.':'DC No'},
  'Rejection Note': {'Ref WorkOrder No.':'Work Order','Rejection Remarks':'Reason'}
};

export function transactionHeader(title, config) {
  const capture = referenceForms[title];
  if (!capture) return [];
  const fields = [...new Set(['Date','Series',capture.party,...capture.fields])].filter(Boolean);
  const names = aliases[title] || {};
  const descriptors = fields.map(label => {
    const proposedKey = Object.hasOwn(names,label) ? names[label] : label;
    // Transaction ID and workflow status belong to the existing register.
    const inSummary = proposedKey !== config.columns[0] && config.fields.includes(proposedKey);
    const key = inSummary ? proposedKey : label;
    return {
      label, key, inSummary, required:inSummary,
      type:referenceInputType(label),
      options:label==='Series' ? capture.series : referenceOptions(title,label)
    };
  });
  return descriptors;
}

export const invoiceHeaderKeys = {
  'Date':'date','Series':'series','Customer':'customer','Consignee':'consignee',
  'Invoice Category':'category','DC Number':'dc','Buyer PO No.':'po','Vehicle No.':'vehicle',
  'Project Name':'project','Terms of payment':'terms','Mode of Dispatch':'dispatch',
  'Country of Shipment/Destination':'country','Kind Attention':'attention','Scope Of Work':'scope',
  'Currency Type':'currency','Sales Order Reference':'sourceOrder','Due Date':'dueDate','Tax (%)':'taxRate'
};

// Staff enter measured quantities and actual settlements on the target transaction.
export const actualEntryFields={
  GRN:['Received Qty','Rate'],
  'Outsource Receipt':['Received Qty','Rate'],
  'Production Output':['Good Qty','Reject Qty'],
  'Customer Payments':['Amount'],
  'Vendor Payments':['Amount']
};
const source = (module, reference, fields = {}, relatedReference) => ({module,reference,fields,relatedReference});
export const referenceFetch = {
  'Sales Quotations': [
    source('Sales Orders','',{'PO Number':'Customer PO'}),
    source('Sales Enquiries','Enquiry',{'Enq Ref date.':'Date'})
  ],
  'Sales Orders': [source('Sales Quotations','Quotation No',{'Quotation Date':'Date'}),source('Job Work Inward','')],
  'Purchase Orders': [source('Purchase Indents','Indent No'),source('Outsource Issue DC','')],
  'GRN': [source('Purchase Orders','PO No',{'PO Ref. Dt.':'PO Date'})],
  'Purchase': [source('GRN','',{},'PO No')],
  'Work Order': [source('Sales Orders','SO No',{'PO Number':'Customer PO','Project Name/Code':'Project Name/Code'}),source('Rejection Note','')],
  'Production Output': [source('Work Order','WO No',{'PO Number':'PO Number'})],
  'Outward QC': [source('Production Output','Output No',{'PO Number':'PO Number'})],
  'Delivery Challan': [source('Sales Orders','SO No',{'PO Number':'Customer PO','Project Name':'Project Name/Code'})],
  'Sales Invoice': [source('Sales Orders','',{'po':'Customer PO','project':'Project Name/Code'})],
  'Proforma Invoice': [source('Sales Orders','SO No',{'PO Number':'Customer PO'})],
  'Sales Return': [source('Sales Invoice','Invoice')],
  'Customer Payments': [source('Sales Invoice','Invoice')],
  'Vendor Payments': [source('Purchase','Invoice')],
  'Credit Note': [source('Sales Invoice','Invoice',{'DC Number':'dc','Buyer PO No.':'po'})],
  'Outsource Receipt': [source('Outsource Issue DC','Issue DC')],
  'Inward Quality': [source('Job Work Inward','',{'PO Number':'PO Number'})],
  'Material Issue': [source('Material Request','',{},'Work Order')]
};

// A trailer shares the original row's atomic write and module permissions.
// All existing register, stock, workflow and SQL column indices keep their positions.
export const detailsFromRow = (columns, row) => {
  const details = row?.[columns.length];
  return details?.version === 1 ? details : null;
};
export const rowStatus = row => row?.at?.(-1)?.version === 1 ? row.at(-2) : row?.at?.(-1);
export const rowMatchesColumns = (columns,row) => Array.isArray(row) && (
  row.length === columns.length || (row.length === columns.length+1 && Boolean(detailsFromRow(columns,row)))
);

export function applyReferenceFetch(form, values) {
  const next = {...form};
  for (const [key,value] of Object.entries(values)) {
    if ((!String(next[key]??'').trim() || next[key]==='-') && String(value??'').trim() && value!=='-') {
      next[key]=String(value);
    }
  }
  return next;
}
