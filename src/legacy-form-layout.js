const titles={
  'Sales Enquiries':'Sales Enquiry','Sales Quotations':'Sales Quotation','Sales Orders':'Sales Order',
  'Purchase Orders':'Purchase Order','Purchase Indents':'Purchase Indent','GRN':'Goods Receipt Note',
  'Outsource Issue DC':'Outsource Issue','Job Work Return DC':'Job Work Return','Route Cards':'Route Card',
  'Scrap Entry':'SCRAP Entry'
};
export const legacyDocumentName=title=>titles[title]||title;

const lineFields={
  'Sales Enquiries':['Product','Qty'],'Sales Quotations':['Product','Qty'],'Sales Orders':['Product','Qty'],
  'Purchase Orders':['Item','Qty'],'Purchase Indents':['Item','Qty'],'GRN':['Item','Received Qty'],
  'Purchase':['Item','Qty'],'Work Order':['Product','Qty'],'Material Request':['Item','Qty'],
  'Material Issue':['Item','Qty'],'Production Output':['Product','Good Qty'],'Delivery Challan':['Product','Qty'],
  'Job Work Inward':['Material','Qty'],'Job Work Return DC':['Product','Qty'],'Outsource Issue DC':['Product','Qty'],
  'Outsource Receipt':['Product','Received Qty'],'Inward Quality Rejection':['Item','Rejected Qty'],
  'Rejection Note':['Product','Qty'],'Sales Return':['Product','Qty'],'Proforma Invoice':['Product','Qty'],
  'Credit Note':['Product','Qty'],'Scrap Entry':['Material','Qty'],'Opening Stock':['Item','Qty'],
  'Excess Stock':['Item','Excess Qty'],'Shortage Stock':['Item','Shortage Qty']
};

export function legacyLineKeys(title) {
  const fields=lineFields[title];
  return fields?{description:fields[0],quantity:fields[1],uom:'UOM',rate:'Rate'}:null;
}

export function legacyFieldClass(field,party,previous) {
  if(field==='Date')return 'legacy-date';
  if(field==='Series')return 'legacy-series';
  if(field===party)return 'legacy-party';
  if(field==='Consignee')return 'legacy-consignee';
  if(previous===party||previous==='Consignee'||/remarks/i.test(previous||'')||previous==='Invoice Category')return 'legacy-new-row';
  return '';
}
