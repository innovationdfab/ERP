// i-MANTRA feature-list integration: additive document definitions and safeguards.
// Existing ERP modules and stored documents retain their original schemas and keys.
const doc = (columns, statuses, next, fields=columns.slice(0,-1)) => ({columns,fields,statuses,...(next?{next}:{})});
export const imantraTransactions = {
  'Import Purchase': doc(['Import No','Vendor','PO No','Item','Qty','Currency','Customs Value','Status'],['Draft','Approval Pending','Approved','Received'],'GRN'),
  'Procurement Planning': doc(['Plan No','Item','Required Qty','Available Qty','Need Date','Department','Status'],['Draft','Reviewed','Approved','Released'],'Purchase Indents'),
  'Procurement Schedule': doc(['Schedule No','PO No','Vendor','Item','Qty','Planned Date','Status'],['Draft','Confirmed','Partially Delivered','Completed'],'GRN'),
  'Dispatch Schedule': doc(['Schedule No','SO No','Customer','Product','Qty','Scheduled Date','Status'],['Draft','Confirmed','Ready','Dispatched'],'Delivery Challan'),
  'Production Schedule': doc(['Schedule No','WO No','Product','Qty','Machine','Planned Date','Status'],['Draft','Released','Running','Completed'],'Input to Production'),
  'Project Planning': doc(['Project No','Customer','SO No','Start Date','Target Date','Owner','Status'],['Draft','Approved','Active','Completed'],'Project Order'),
  'Job Order': doc(['Job No','Work Order','Vendor','Process','Qty','Required Date','Status'],['Draft','Approved','Issued','Completed'],'Outsource Issue DC'),
  'Jobwork Material Issue': doc(['Issue No','Job No','Vendor','Item','Qty','Issue Date','Status'],['Draft','Approved','Issued','Closed'],'Jobwork Material Receipt'),
  'Jobwork Material Receipt': doc(['Receipt No','Issue No','Vendor','Item','Received Qty','Receipt Date','Status'],['Draft','Received','QC Pending','Accepted'],'Job Work QC'),
  'Service Invoice': doc(['Invoice No','Vendor','Job No','Service','Amount','Invoice Date','Status'],['Draft','Approval Pending','Approved','Posted'],'Vendor Payments'),
  'Input to Production': doc(['Input No','WO No','Item','Qty','Issue No','Date','Status'],['Draft','Approved','Issued','Consumed'],'Stage Consumption'),
  'Stage Receipt': doc(['Receipt No','WO No','Operation','Machine','Good Qty','Reject Qty','Status'],['Draft','Recorded','Inspected','Completed'],'In-process QC'),
  'Stage Consumption': doc(['Consumption No','WO No','Operation','Item','Consumed Qty','Input No','Status'],['Draft','Recorded','Approved','Posted'],'Stage Receipt'),
  'Excess Issue': doc(['Issue No','WO No','Item','Qty','Reason','Store','Status'],['Draft','Approval Pending','Approved','Issued'],'Input to Production'),
  'Return to Store': doc(['Return No','WO No','Item','Qty','Warehouse','Date','Status'],['Draft','Inspected','Accepted','Posted']),
  'Dispatch Intimation': doc(['Intimation No','SO No','Customer','Product','Qty','Planned Date','Status'],['Draft','Approved','Sent','Acknowledged'],'Dispatch Schedule'),
  'BOM-Based Work Order': doc(['BOM WO No','BOM No','Product','Qty','Start Date','Target Date','Status'],['Draft','Approved','Released','Completed'],'Work Order'),
  'Stock Adjustment': doc(['Adjustment No','Item','Warehouse','Quantity Change','Reason','Date','Status'],['Draft','Approval Pending','Approved','Posted']),
  'Material Reserve': doc(['Reserve No','WO No','Item','Qty','Warehouse','Required Date','Status'],['Draft','Approved','Reserved','Released'],'Material Request'),
  'Material Unreserved': doc(['Unreserve No','Reserve No','Item','Qty','Warehouse','Date','Status'],['Draft','Approved','Released']),
  'Terminate Order': doc(['Termination No','SO No','Customer','Reason','Date','Approved By','Status'],['Draft','Approval Pending','Approved','Closed']),
  'Project Order': doc(['Project Order No','Project No','Customer','SO No','Value','Due Date','Status'],['Draft','Approved','Running','Completed'],'Work Order'),
  'Delivery Channel': doc(['Channel Code','Channel','Transporter','Contact','Region','Status'],['Draft','Active','Inactive']),
  'Purchase Return': doc(['Return No','GRN No','Vendor','Item','Qty','Reason','Status'],['Draft','Approval Pending','Approved','Returned']),
  'Pick Slip': doc(['Pick No','SO No','Warehouse','Item','Qty','Picker','Status'],['Draft','Allocated','Picked','Confirmed'],'Dispatch Intimation'),
  'Put Away': doc(['Putaway No','GRN No','Item','Qty','Warehouse','Rack','Status'],['Draft','QC Cleared','Put Away','Completed']),
  'In-process QC': doc(['QC No','WO No','Operation','Qty','Inspector','Disposition','Status'],['Pending','In Inspection','Passed','Rejected']),
  'Job Work QC': doc(['QC No','Receipt No','Vendor','Item','Qty','Inspector','Status'],['Pending','In Inspection','Passed','Rejected']),
};

export const imantraForwardStatuses = {
  'Import Purchase':['Approved','Received'],
  'Procurement Planning':['Approved','Released'], 'Procurement Schedule':['Confirmed','Partially Delivered'],
  'Dispatch Schedule':['Ready','Dispatched'], 'Production Schedule':['Released','Running'],
  'Project Planning':['Approved','Active'], 'Job Order':['Approved','Issued'],
  'Jobwork Material Issue':['Issued'], 'Jobwork Material Receipt':['Accepted'],
  'Service Invoice':['Posted'], 'Input to Production':['Issued','Consumed'],
  'Stage Receipt':['Completed'], 'Stage Consumption':['Approved','Posted'],
  'Excess Issue':['Issued'], 'Dispatch Intimation':['Sent','Acknowledged'],
  'BOM-Based Work Order':['Released'], 'Material Reserve':['Reserved'],
  'Project Order':['Approved','Running'], 'Pick Slip':['Confirmed'],
};

const numericFields=/^(qty|received qty|good qty|reject qty|consumed qty|required qty|available qty|quantity change|customs value|value|amount)$/i;
const sourceByField={
  'PO No':'Purchase Orders','SO No':'Sales Orders','WO No':'Work Order',
  'GRN No':'GRN','BOM No':'Production BOM','Job No':'Job Order',
  'Issue No':'Jobwork Material Issue','Input No':'Input to Production',
  'Reserve No':'Material Reserve','Project No':'Project Planning',
  'Receipt No':'Jobwork Material Receipt',
};
export const imantraReferenceSource = sourceByField;
export function validateImantraDocument(title, record, sourceLookup){
  const def=imantraTransactions[title];if(!def)return null;
  for(const field of def.fields){
    const value=String(record[field]??'').trim();
    if(!value || value==='-')return `${field} is required.`;
    if(numericFields.test(field)){
      const amount=Number(value);
      if(!Number.isFinite(amount))return `${field} must be a valid number.`;
      if(field==='Quantity Change' ? amount===0 : amount<0)return `${field} must be ${field==='Quantity Change'?'nonzero':'zero or greater'}.`;
      if(/qty/i.test(field)&&!['Reject Qty','Available Qty'].includes(field)&&amount===0)return `${field} must be greater than zero.`;
    }
  }
  for(const field of def.fields.slice(1)){
    const source=sourceByField[field];if(!source)continue;
    const ref=String(record[field]||'').trim();
    if(ref && typeof sourceLookup==='function' && !sourceLookup(source,field,ref))return `${field} ${ref} does not exist in ${source}.`;
  }
  const good=Number(record['Good Qty']||0),reject=Number(record['Reject Qty']||0);
  if(Number.isFinite(good)&&Number.isFinite(reject)&&(good<0||reject<0))return 'Quality quantities cannot be negative.';
  return null;
}

export const imantraReportDefinitions={
  'Executed Sales Order Register':{source:'Sales Orders',columns:['SO No','Customer','Product','Qty','Status'],statuses:['Completed']},
  'Terminated Sales Order Register':{source:'Terminate Order',columns:['Termination No','SO No','Customer','Reason','Status']},
  'Project Order Register':{source:'Project Order',columns:['Project Order No','Project No','Customer','Value','Status']},
  'Pending Project Order Register':{source:'Project Order',columns:['Project Order No','Project No','Customer','Due Date','Status'],excludeStatuses:['Completed']},
  'Executed Purchase Order Register':{source:'Purchase Orders',columns:['PO No','Vendor','Amount','Delivery Date','Status'],statuses:['Received','Closed']},
  'Terminated Purchase Order Register':{source:'Purchase Orders',columns:['PO No','Vendor','Amount','Status'],statuses:['Closed']},
  'Procurement Registers':{source:'Procurement Planning',columns:['Plan No','Item','Required Qty','Need Date','Status']},
  'Planned Vs Work Orders':{source:'Production Schedule',columns:['Schedule No','WO No','Product','Qty','Planned Date','Status']},
  'Procurement Vs Planned':{source:'Procurement Schedule',columns:['Schedule No','PO No','Vendor','Qty','Planned Date','Status']},
  'Project Execution Vs Planned':{source:'Project Planning',columns:['Project No','Customer','Start Date','Target Date','Status']},
  'Dispatch Vs Planned':{source:'Dispatch Schedule',columns:['Schedule No','SO No','Customer','Qty','Scheduled Date','Status']},
  'Production Vs Planned':{source:'Production Schedule',columns:['Schedule No','WO No','Product','Qty','Planned Date','Status']},
  'Material Issue Register':{source:'Material Issue',columns:['Issue No','Work Order','Item','Qty','Status']},
  'Jobwork Receipt Register':{source:'Jobwork Material Receipt',columns:['Receipt No','Issue No','Vendor','Received Qty','Status']},
  'BOM Register':{source:'Production BOM',columns:['BOM No','Product','Revision','Status']},
  'Production Register':{source:'Production Output',columns:['Output No','WO No','Product','Good Qty','Reject Qty','Status']},
  'Inward QC Status Register':{source:'Inward QC',columns:['QC No','GRN No','Item','Qty','Status']},
  'In-process QC Status Register':{source:'In-process QC',columns:['QC No','WO No','Operation','Qty','Status']},
  'Outward QC Status Register':{source:'Outward QC',columns:['QC No','Output No','Product','Qty','Status']},
  'Job Work QC Register':{source:'Job Work QC',columns:['QC No','Receipt No','Vendor','Qty','Status']},
  'Stock List':{source:'Opening Stock',columns:['Entry No','Item','Warehouse','Qty','Rate','Status']},
  'Inventory Ageing':{source:'GRN',columns:['GRN No','Item','Received Qty','QC Status']},
  'Stock Valuation':{source:'Opening Stock',columns:['Entry No','Item','Qty','Rate','Status']},
  'WIP Stock':{source:'Input to Production',columns:['Input No','WO No','Item','Qty','Status']},
  'Work-Order-Wise Order':{source:'Work Order',columns:['WO No','SO No','Product','Qty','Status']},
  'Work Order Status':{source:'Work Order',columns:['WO No','SO No','Product','Qty','Status']},
  'Daily Production Report':{source:'Production Output',columns:['Output No','WO No','Product','Good Qty','Reject Qty','Status']},
  'Excess Consumption Register':{source:'Excess Issue',columns:['Issue No','WO No','Item','Qty','Status']},
  'Short Consumption Register':{source:'Return to Store',columns:['Return No','WO No','Item','Qty','Status']},
  'Consumption Against WO':{source:'Stage Consumption',columns:['Consumption No','WO No','Item','Consumed Qty','Status']},
};

export function imantraReportRows(reportKey, readRows, configs){
  const definition=imantraReportDefinitions[reportKey];if(!definition)return null;
  const config=configs[definition.source];if(!config)return [];
  const statusIndex=config.columns.findIndex(c=>/status|stage|decision/i.test(c));
  return (readRows(`dfab-erp-${definition.source}`)||[]).filter(Array.isArray)
    .filter(row=>statusIndex<0 || ((!definition.statuses||definition.statuses.includes(row[statusIndex]))&&(!definition.excludeStatuses||!definition.excludeStatuses.includes(row[statusIndex]))))
    .map(row=>definition.columns.map(name=>{const index=config.columns.indexOf(name);return index<0?'':row[index]??''}));
}

/** Copy verified source facts into a new *draft* linked document; no receipt/posting is implied. */
export function imantraForwardPrefill(sourceTitle,targetTitle,source){
  const mapping={
    'Procurement Planning':{'Purchase Indents':{Item:source.Item,Qty:source['Required Qty'],'Required Date':source['Need Date'],Department:source.Department}},
    'Procurement Schedule':{'GRN':{'PO No':source['PO No'],Vendor:source.Vendor,Item:source.Item,'Received Qty':''}},
    'Dispatch Intimation':{'Dispatch Schedule':{'SO No':source['SO No'],Customer:source.Customer,Product:source.Product,Qty:source.Qty,'Scheduled Date':source['Planned Date']}},
    'Dispatch Schedule':{'Delivery Challan':{'SO No':source['SO No'],Customer:source.Customer,Product:source.Product,Qty:source.Qty}},
    'Job Order':{'Outsource Issue DC':{Vendor:source.Vendor,'Work Order':source['Work Order'],Process:source.Process,Qty:source.Qty}},
    'Jobwork Material Issue':{'Jobwork Material Receipt':{'Issue No':source['Issue No'],Vendor:source.Vendor,Item:source.Item,'Received Qty':''}},
    'Production Schedule':{'Input to Production':{'WO No':source['WO No'],Item:source.Product,Qty:source.Qty}},
    'Input to Production':{'Stage Consumption':{'WO No':source['WO No'],Item:source.Item,'Input No':source['Input No'],'Consumed Qty':''}},
    'Stage Consumption':{'Stage Receipt':{'WO No':source['WO No'],Operation:source.Operation,'Good Qty':''}},
    'Stage Receipt':{'In-process QC':{'WO No':source['WO No'],Operation:source.Operation,Qty:source['Good Qty']}},
    'Pick Slip':{'Dispatch Intimation':{'SO No':source['SO No'],Product:source.Item,Qty:source.Qty}},
    'Service Invoice':{'Vendor Payments':{Vendor:source.Vendor,Invoice:source['Invoice No'],Amount:source.Amount}},
    'Project Planning':{'Project Order':{'Project No':source['Project No'],Customer:source.Customer}},
    'BOM-Based Work Order':{'Work Order':{Product:source.Product,Qty:source.Qty}},
    'Project Order':{'Work Order':{'SO No':source['SO No']}},
    'Excess Issue':{'Input to Production':{'WO No':source['WO No'],Item:source.Item,Qty:source.Qty}},
    'Material Reserve':{'Material Request':{'Work Order':source['WO No'],Item:source.Item,Qty:source.Qty}},
  };
  return Object.fromEntries(Object.entries(mapping[sourceTitle]?.[targetTitle]||{}).filter(([,value])=>value!==undefined));
}
