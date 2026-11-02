import {SOP_FLOWS,FLOW_LABELS,nextStages} from './process-schema.js';
import {fetchSourceTypes} from './process-fetch.js';

// Existing Transactions navigation; labels and routes are deliberately retained.
export const TRANSACTION_SECTIONS={
 Purchase:['Purchase Orders','Vendor Price List','Purchase Indents','Customer Price List','Indent To Order','GRN','Purchase','Tally Link - Purchase'],
 Marketing:['CRM Pipeline','Sales Enquiries','Sales Quotations','Sales Orders'],
 Sales:['Sales Invoice','Delivery Challan','Tally Link - Sales','Sales Return','Proforma Invoice','Credit Note'],
 Stores:['Material Issue','Scrap Entry','Opening Stock','Excess Stock','Shortage Stock','Production Output'],
 'Quality Control':['Inward QC','Outward QC','Inward Quality Rejection','Inward Quality'],
 Production:['Work Order','Outsource Issue DC','Job Work Inward','Job Work Return DC','Outsource Receipt','Material Request','Route Cards','Rejection Note'],
 Approvals:['Pending Approvals'],Payments:['Vendor Payments','Customer Payments']
};
export function transactionSection(title){return Object.keys(TRANSACTION_SECTIONS).find(section=>TRANSACTION_SECTIONS[section].includes(title))||'';}
export function transactionPath(title){return ['Transactions',transactionSection(title),title].filter(Boolean);}
export function transactionContext(doc,links=[]){
 const sources=fetchSourceTypes(doc.module),next=nextStages(doc);
 const incoming=links.find(link=>link.to===doc.module&&link.created===doc.number);
 const source=doc.source||(incoming?{module:incoming.from,number:incoming.reference}:null);
 return {
  section:transactionSection(doc.module),path:transactionPath(doc.module),sources,next,
  source,
  process:SOP_FLOWS[doc.flow]?.includes(doc.module)?FLOW_LABELS[doc.flow]:'',
  sourceText:source?`${source.module} · ${source.number}`:sources.length?sources.join(' / '):'Manual entry',
  nextText:next.length?next.join(' / '):'No next transaction'
 };
}
