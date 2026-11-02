/** Field labels and options inspected in the signed-in iMANTRA UI on 2 Nov 2026.
 * SOP-only controls are kept in a separate Workflow section. */
const split = text => text ? text.split('|') : [];
const quality = 'Pipe Drawing No & Rev|TTL Ref No.|Material|WPS Used|Weder Code|Electrode/Filler rod used|Project Name|PO Number|C Number|A Number|Next Task Assigned to|Target Date';
const shipping = 'DC Number|Buyer PO No.|Vehicle No.|Terms of payment|DC date|Buyer Ref Date|Mode of Dispatch|Date Of Supply|Country of Shipment/Destination|E-Way Bill No|E-Way Bill Date|Vendor Code|MGP/Customer DC No|MGP/Customer DC Date|IRN No|Lut No|Ack No|Ack Date|Transporter Name|Project Name|Valid Upto|Kind Attention|Quotation No|Quotation Date|PO Date|Managed By|Scope Of Work|C Number|A Number|Signature Required|Incoterms|Destination|Currency Type';
const raw = {
 'Sales Enquiries':['SE','Prospect','LOCAL','Enquiry Category|Enquiry Remarks|Next Task Assigned to|Enquiry Reference No|Enquiry Reference Date|Target Date|Managed By|Kind Attention|Scope Of Work|Priority',false],
 'Sales Quotations':['SQ','Prospect','LOCAL','Quotation Category|Quotation Remarks|Enq Ref date.|Enq Ref. No.|Next Task Assigned to|Payment Terms|Mode of Enq.|PO Number|Work Order Number|Project Name|Ref Contact Person|Taxes|Inspection|Delivery Term|Quotation Validity|Lead Time|Managed By|Target Date|Scope Of Work|Priority|Currency Type',true,'Excel Copy'],
 'Sales Orders':['SO','Customer','LOCAL','Order Remarks|Customer PO Dt.|Project Name/Code|PO Number|Expected Delivery Date.|Kind Attention|Managed By|Quotation No|Quotation Date|Next Task Assigned to|Target Date|Scope Of Work|C Number|A Number',true,'Order Copy'],
 'Purchase Orders':['PO','Vendor','PURCHASE ORDER|OTHER','Category|Department|Order Remarks|Invoice No.|Invoice Date|Delivery Need Date|Work Order Number|Project Name|Approved By|Purchased By|Signature Required|Requested By',true,'Quotation Document'],
 'Purchase Indents':['PI','Vendor','INDENT','Indent Remarks|Ref Tran No',true],
 'GRN':['GRN','Vendor','GRN','Category|Department|MRN Remarks|Supplier Invoice No.|Supplier Invoice Dt.|PO Ref No|PO Ref. Dt.|Work Order No',false,'Weighment Slip|Inspection Report'],
 'Work Order':['WK','Customer','WORK ORDER|JOB ORDER','Category|Remarks|SO Ref No|Project Name/Code|PO Number|Managed By|Next Task Assigned to|Target Date|Scope Of Work',true],
 'Material Request':['MR','Customer','MATERIAL REQUEST','Remarks|Work Order No.|PO Number',false],
 'Material Issue':['MI','Vendor','MATERIAL ISSUE|MATERIAL SCRAP','Departments|Remarks|Work Order No.|Project Name/Code|Sale Order No|PO Number',false],
 'Production Output':['OP','Customer','OUTPUT','Remarks|PO Number|Ref Work Order Number|Target Date|Next Task Assigned to',false],
 'Outward QC':['OQ','Vendor','Outward QC',`${quality}|Stage|Weld Repair Drawing Number|Pipe Welding Drawing Number|Dispatch Date|MPT Test Date|Remarks`,false],
 'Delivery Challan':['DC','Vendor','DELIVERY CHALLAN','Consignee|Category|Approximate Goods Value|Tran Ref No|PO Number|MGP/Customer DC Number|Project Name|Eway Bill No|Vehicle No.|Transporter Name|Eway Bill Date|Valid Upto|Kind Attention|Remarks|Bill Of Loading/LR-RR No.|MGP/Customer Dc Date|PO Date|Managed By|Scope Of Work|C Number|A Number',true],
 'Sales Invoice':['SI','Customer','LOCAL|EXPORT',`Invoice Category|${shipping}`,false,'Documents Upload'],
 'Purchase':['IP','Vendor','PURCHASE INVOICE','Order Remarks|Invoice No.|Invoice Date|Sale Order Number|Project Name|Approved By|Purchased By|Work Order Number',true],
 'Job Work Inward':['JI','Vendor','Job Work Inward','Remarks|PO Number|DC NO.|DC Date.|Approximate Goods Value.|Kind Attention|SUB Vendor|Project Name|C Number|A Number|Next Task Assigned to|Target Date',true,'Attachment'],
 'Job Work Return DC':['RJ','Vendor','Job Work Return','Remarks|E-Way Bill No|E-Way Bill Date|Valid Upto|Transporter Name|Vehicle No.|Estimated Goods Value',false],
 'Outsource Issue DC':['WI','Vendor','Outsource Issue','Remarks|Our Po No|Due Date|Estimated Value|Transport By|Vehicle No|e-Way Bill No|Project Name|E-Way Bill Date|Valid Upto|Delivery BY',true],
 'Outsource Receipt':['WR','Vendor','Outsource Receipt','Remarks|Vendor Invoice Number|Vendor Invoice Basic Value|Vendor Invoice Taxable Value|Vendor DC Number|Vendor DC Date|Invoice Date',false,'Attachment'],
 'Inward Quality':['QI','Supplier','Inward QC',`${quality}|Remarks`,false],
 'Inward Quality Rejection':['IR','Supplier','Inward Quality Rejection','Remarks|Supplier Invoice No.|Supplier Invoice Dt.',false],
 'Rejection Note':['NR','','Rejection Note','Remarks|Ref Process Name|Ref WorkOrder No.|Rejection Type|Rejection Remarks',true],
 'Sales Return':['SR','Customer','REGULAR','Consignee',false],
 'Proforma Invoice':['PR','Customer','Proforma Invoice','Consignee|Invoice Remarks|Date Of Supply|Project Name|Kind Attention|Quotation No|Quotation Date|Advance Payment Amount|PO Number|Payment Terms',false],
 'Credit Note':['CN','Customer','Credit Note','Consignee|Category|DC Number|Buyer PO No.|Vehicle No.|Terms of payment|DC date|Buyer Ref Date|Transportation Mode|Date Of Supply|Place Of Supply|E-Way Bill No|E-Way Bill Date|Vendor Code|Reference DC No|Reference DC Date|IRN No|Tax Payable on Reverse Charge|TAN|Lut No|Ack No|Ack Date|Transporter ID|Transporter Name|Reference Tran No',true],
 'Scrap Entry':['SP','Customer','SCRAP','Scrap Category|Scrap Remarks',false],
 'Opening Stock':['OS','Vendor','STOCK','Remarks',false],
 'Excess Stock':['ES','Vendor','Excess','Remarks',false],
 'Shortage Stock':['SS','Vendor','Shortage','Remarks',false],
 // These two screens have distinct layouts in iMANTRA; their inspection/operation
 // controls are deliberately separate from the common commercial header.
 'Inward QC':['IQC','Supplier','Inward QC','Supplier Invoice No.|Supplier Invoice Dt.|PO Ref No|PO Ref. Dt.|GRN No|Job Inward No|Inspector|Inspection Remarks',false],
 'Route Cards':['RC','Customer','Route Card','WO No|Master Route Card No|Revision|Project Name|Managed By',false]
};
export const schemas=Object.fromEntries(Object.entries(raw).map(([name,[code,party,series,fields,approval,files]])=>[name,{name,code,party,series:split(series),fields:split(fields),approval,files:split(files)}]));
export const SOP_FLOWS={
 manufacturing:['Sales Enquiries','Sales Quotations','Sales Orders','Purchase Orders','GRN','Inward QC','Work Order','Route Cards','Production Output','Outward QC','Delivery Challan','Sales Invoice','Customer Payments'],
 labour:['Job Work Inward','Inward QC','Sales Orders','Work Order','Route Cards','Production Output','Outward QC','Delivery Challan','Sales Invoice','Customer Payments']
};
export const FLOW_LABELS={manufacturing:'Manufacturing & Supply',labour:'Labour Job Work'};
export const DEPARTMENTS=['Sales / RFQ','Accounts','Finance / Purchase','Stores','Quality (QC)','Production / NPD'];
export const OWNERS={'Sales Enquiries':'Sales / RFQ','Sales Quotations':'Sales / RFQ','Sales Orders':'Accounts','Purchase Orders':'Finance / Purchase','GRN':'Stores','Inward QC':'Quality (QC)','Work Order':'Production / NPD','Route Cards':'Production / NPD','Production Output':'Production / NPD','Outward QC':'Quality (QC)','Delivery Challan':'Accounts','Sales Invoice':'Accounts','Customer Payments':'Accounts'};
export const sideKey=name=>`dfab-process-${name}`;
export const rowKey=name=>name==='Sales Invoice'?'dfab-erp-sales-invoices-v2':`dfab-erp-${name}`;
export function optionsFor(name,label){
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
export function inputType(label){
 if(/date|\bdt\.?|valid upto/i.test(label))return 'date';
 if(/amount|goods value|estimated value/i.test(label))return 'number';
 return /remarks|scope of work/i.test(label)?'textarea':'text';
}
export function nextStages(doc){
 const flow=SOP_FLOWS[doc.flow]||SOP_FLOWS.manufacturing,index=flow.indexOf(doc.module);
 const primary=doc.module==='Route Cards'&&doc.productionIncluded?'Outward QC':index>=0?flow[index+1]:null;
 const branches={'Purchase Indents':'Purchase Orders','Material Request':'Material Issue','Material Issue':'Route Cards','Outsource Issue DC':'Outsource Receipt','Outsource Receipt':'Inward QC','Sales Return':'Credit Note','Job Work Return DC':'Sales Invoice','Purchase':'Vendor Payments'};
 const result=primary?[primary]:branches[doc.module]?[branches[doc.module]]:[];
 if(doc.module==='Work Order')result.push('Material Request','Outsource Issue DC');
 if(doc.module==='Inward QC'&&doc.flow!=='labour')result.push('Purchase');
 if(doc.module==='Route Cards')result.push('Outsource Issue DC');
 return [...new Set(result)];
}
export const newLine=()=>({id:crypto.randomUUID(),code:'',description:'',quantity:'1',uom:'',rate:'0',discount:'0',cgst:'9',sgst:'9',igst:'0',hsn:'',group:'',type:'',drawing:'',revision:'',remarks:''});
export const newOperation=()=>({id:crypto.randomUUID(),process:'',type:'In-house',workcenter:'',machine:'',vendor:'',qcRequired:true,quantity:'0',status:'Pending',qcStatus:'Pending',remarks:''});
