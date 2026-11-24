import { isoDate, todayISO } from './erp-utils.js';
import { normalizeReference, numberValue } from './workflow-integrity.js';
import { postedStockMovements, stockMovementSources } from './imantra-stock.js';

export const extensionPages={
  'Reorder Planning':{sources:['Products','Vendors','Purchase Indents','Purchase Orders','GRN',...stockMovementSources]},
  'Receivables Ageing':{sources:['Sales Invoice','Customer Payments','Credit Note']},
  'Collection Follow-ups':{sources:['Sales Invoice','Customer Payments','Credit Note']},
  'Customer Statements':{sources:['Sales Invoice','Customer Payments','Credit Note']}
};
export const policyKey='dfab-erp-reorder-policies-v1';
export const followupKey='dfab-erp-collection-followups-v1';
const money=value=>Math.round(value*100)/100;
export const daysBetween=(first,last)=>Math.round((Date.parse(last)-Date.parse(first))/86400000);
export const addDays=(date,days)=>new Date(Date.parse(date)+days*86400000).toISOString().slice(0,10);
export const extensionAllowed=(title,canRead)=>!!extensionPages[title]&&[title,...new Set(extensionPages[title].sources)].every(canRead);

export function productIndex(products){
  const codes=new Map(products.filter(Array.isArray).map(row=>[normalizeReference(row[0]),row]));
  const names=new Map();
  for(const row of codes.values()){
    const name=normalizeReference(row[1]);
    if(name)names.set(name,names.has(name)?null:row);
  }
  return value=>codes.get(normalizeReference(value))||names.get(normalizeReference(value));
}

export function reorderRows(policies,readRows,readDocuments){
  const products=readRows('dfab-erp-products-v3');
  const resolve=productIndex(products);
  const amounts=new Map();
  const add=(item,field,qty)=>{
    const product=resolve(item);
    if(!product)return;
    const code=normalizeReference(product[0]);
    const sums=amounts.get(code)||{stock:0,onOrder:0,requested:0};
    sums[field]+=qty;
    amounts.set(code,sums);
  };
  for(const move of postedStockMovements(readRows))add(move.item,'stock',move.qty);
  const receipts=readDocuments('GRN');
  const orders=readDocuments('Purchase Orders');
  const linkedIndents=new Set(orders.filter(order=>!['Cancelled','Rejected'].includes(order.fields.Status))
    .map(order=>normalizeReference(order.fields['Indent No'])).filter(Boolean));
  const links=readRows('dfab-workflow-links-v1');
  for(const link of links){
    if(link.from!=='Indent To Order'||link.to!=='Purchase Orders'||!orders.some(order=>normalizeReference(order.number)===normalizeReference(link.created)&&!['Cancelled','Rejected'].includes(order.fields.Status)))continue;
    const parent=links.find(value=>value.from==='Purchase Indents'&&value.to==='Indent To Order'&&normalizeReference(value.created)===normalizeReference(link.reference));
    linkedIndents.add(normalizeReference(parent?.reference||link.reference));
  }
  for(const order of orders){
    if(!['Approved','Sent','Partially Received'].includes(order.fields.Status))continue;
    const qty=numberValue(order.fields.Qty);
    const received=receipts.filter(receipt=>normalizeReference(receipt.fields['PO No'])===normalizeReference(order.number)
      &&['Accepted','Awaiting QC'].includes(receipt.fields['QC Status'])).reduce((sum,receipt)=>sum+(numberValue(receipt.fields['Received Qty'])||0),0);
    if(qty!==null)add(order.fields.Item,'onOrder',Math.max(0,qty-received));
  }
  for(const request of readDocuments('Purchase Indents')){
    if(!linkedIndents.has(normalizeReference(request.number))&&['Draft','Approval Pending','Approved'].includes(request.fields.Status))add(request.fields.Item,'requested',numberValue(request.fields.Qty)||0);
  }
  return policies.map(policy=>{
    const product=resolve(policy.id);
    const totals=amounts.get(normalizeReference(policy.id))||{stock:0,onOrder:0,requested:0};
    const triggered=policy.enabled&&product&&product[6]==='ACTIVE'&&totals.stock<=Number(policy.minimum);
    const quantity=triggered?Math.max(0,Math.round((Number(policy.target)-totals.stock-totals.onOrder-totals.requested)*1e8)/1e8):0;
    return {...policy,product,...totals,quantity,status:!policy.enabled?'Disabled':!product?'Product unavailable':product[6]!=='ACTIVE'?'Product inactive':quantity>0?'Reorder needed':totals.stock<=Number(policy.minimum)?'Covered by requests / orders':'Stock sufficient'};
  });
}

export function validateReorderPolicy(policy,products,vendors){
  if(!products.some(row=>row[0]===policy.id&&row[6]==='ACTIVE'))return 'Select an active product.';
  if(!vendors.some(row=>row[0]===policy.vendor&&row[8]==='ACTIVE'))return 'Select an active preferred vendor.';
  const minimum=numberValue(policy.minimum),target=numberValue(policy.target),lead=numberValue(policy.leadDays);
  if(minimum===null||target===null||minimum<0||target<=minimum)return 'Target stock must be greater than a non-negative reorder point.';
  if(lead===null||!Number.isInteger(lead)||lead<0||lead>365)return 'Lead time must be a whole number from 0 to 365 days.';
  return '';
}

/** Confirmed invoices, posted receipts and posted credit notes share the saved invoice reference. */
export function receivableRows(readDocuments,readDetails,asOn=todayISO()){
  const payments=readDocuments('Customer Payments').filter(({fields})=>['Part Paid','Settled'].includes(fields.Status));
  const credits=readDocuments('Credit Note').filter(({fields})=>fields.Status==='Posted');
  const details=readDetails('dfab-invoice-details-v1');
  return readDocuments('Sales Invoice').filter(({fields})=>fields.Status==='APPROVED').flatMap(invoice=>{
    const form=details[invoice.number]?.form||{};
    const date=isoDate(form.date||invoice.fields.Date);
    const amount=numberValue(invoice.fields.Amount);
    if(!date||date>asOn||amount===null)return [];
    const key=normalizeReference(invoice.number);
    const matches=records=>records.filter(({fields})=>normalizeReference(fields.Invoice)===key);
    const allocated=(records,dateFields)=>{
      let total=0,unknown=0,paid=0,tds=0,ld=0;
      for(const {fields} of matches(records)){
        const postedDate=dateFields.map(field=>isoDate(fields[field])).find(Boolean);
        const amount=numberValue(fields.Amount);
        if(!postedDate||amount===null||amount<0){unknown++;continue;}
        if(postedDate<=asOn){paid+=amount;tds+=numberValue(fields['TDS Amount'])??0;ld+=numberValue(fields['LD Amount'])??0;total+=amount+(numberValue(fields['TDS Amount'])??0)+(numberValue(fields['LD Amount'])??0);}
      }
      return {total:money(total),paid:money(paid),tds:money(tds),ld:money(ld),unknown};
    };
    const receipts=allocated(payments,['Date']);
    const credited=allocated(credits,['Date']);
    const due=isoDate(form.dueDate||form['Due Date']);
    const age=due?Math.max(0,daysBetween(due,asOn)):null;
    const balance=money(amount-receipts.total-credited.total);
    return [{...invoice,customer:invoice.fields.Customer||form.customer,currency:form.currency||'',date,due,amount,
      received:receipts.paid,tds:receipts.tds,ld:receipts.ld,settled:receipts.total,credited:credited.total,balance,age,unknownAllocations:receipts.unknown+credited.unknown,
      bucket:!due?'Due date missing':due>=asOn?'Current':age<=30?'1–30 days':age<=60?'31–60 days':age<=90?'61–90 days':'90+ days'}];
  });
}

export function statementRows(customer,currency,readDocuments,readDetails,asOn){
  return receivableRows(readDocuments,readDetails,asOn)
    .filter(row=>normalizeReference(row.customer)===normalizeReference(customer)&&row.currency===currency)
    .sort((a,b)=>a.date.localeCompare(b.date)||a.number.localeCompare(b.number));
}

export function validateFollowup(form,invoices,editing=false){
  if(!invoices.some(invoice=>invoice.number===form.invoice&&(invoice.balance>0||(editing&&form.status==='Done'))))return 'Select an approved invoice with an outstanding balance.';
  if(!isoDate(form.nextDate))return 'Enter a valid next follow-up date.';
  if(!String(form.owner||'').trim()||String(form.owner).length>120)return 'Enter an owner using at most 120 characters.';
  if(!['Phone','Email','Meeting','Other'].includes(form.channel))return 'Select a contact method.';
  if(!['Open','Done'].includes(form.status))return 'Select a valid follow-up status.';
  if(!String(form.note||'').trim()||String(form.note).length>2000)return 'Enter a note using at most 2,000 characters.';
  return '';
}
