import { isoDate, todayISO } from './erp-utils.js';
import { documentReportRows, hasDocumentValue } from './document-data.js';
import { normalizeReference } from './workflow-integrity.js';
import { postedStockMovements, stockMovementSources } from './imantra-stock.js';

export const operationPages={
  'PO Number Details':{requires:['Purchase Orders'],columns:['PO Number','Vendor','Item','Ordered Qty','Delivery Date','Status']},
  'SO Number Details':{requires:['Sales Orders'],columns:['Sales Order','Customer','Customer PO','Product','Order Qty','Delivery Date','Status']},
  'RM Inward and Outward':{requires:['Products',...stockMovementSources],columns:['Reference','Date','Material','Movement','UOM','Inward Qty','Outward Qty']},
  'Route Card Monitoring':{requires:['Route Cards'],columns:['Route Card','Work Order','Product','Operation','Machine','Completed Qty','Status']},
  'Customer Payment Overdue':{requires:['Sales Invoice','Customer Payments'],columns:['Invoice','Customer','Due Date','Days Overdue','Invoice Amount','Received Amount','Balance','Currency']}
};

export function operationRows(page,{readDocuments,readRows,readObject,canRead,today=todayISO()}){
  const row=(values,module,reference)=>({values,module,reference});
  if(page==='PO Number Details')return readDocuments('Purchase Orders').map(({number,fields:f})=>
    row([number,f.Vendor,f.Item,f.Qty,f['Delivery Date'],f.Status],'Purchase Orders',number));
  if(page==='SO Number Details')return readDocuments('Sales Orders').map(({number,fields:f})=>
    row([number,f.Customer,f['Customer PO'],f.Product,f.Qty,f.Delivery,f.Status],'Sales Orders',number));
  if(page==='Route Card Monitoring'){
    const orders=canRead('Work Order')?new Map(readDocuments('Work Order').map(order=>[normalizeReference(order.number),order.fields])):new Map();
    return readDocuments('Route Cards').map(({number,fields:f})=>{
      const work=orders.get(normalizeReference(f['WO No']));
      return row([number,f['WO No'],hasDocumentValue(f.Product)?f.Product:work?.Product,f.Operation,hasDocumentValue(f.Machine)?f.Machine:work?.Machine,f['Completed Qty'],f.Status],'Route Cards',number);
    });
  }
  if(page==='RM Inward and Outward'){
    const raw=readRows('dfab-erp-products-v3').filter(record=>Array.isArray(record)&&/^raw[\s_-]*materials?$/i.test(String(record[2]||'').trim()));
    const byCode=new Map(raw.map(item=>[normalizeReference(item[0]),item]));
    const byName=new Map();
    const usedNames=new Set();
    for(const product of readRows('dfab-erp-products-v3')){
      if(!Array.isArray(product))continue;
      const name=normalizeReference(product[1]);
      if(!name)continue;
      if(usedNames.has(name))byName.delete(name);
      else if(byCode.has(normalizeReference(product[0])))byName.set(name,product);
      usedNames.add(name);
    }
    return postedStockMovements(readRows).sort((a,b)=>b.date.localeCompare(a.date)).flatMap(move=>{
      const material=byCode.get(normalizeReference(move.item))||byName.get(normalizeReference(move.item));
      return material?[row([move.reference,move.date,material[1]||material[0],move.source,material[4],
        Math.max(0,move.qty),Math.max(0,-move.qty)],move.source,move.reference)]:[];
    });
  }
  if(page==='Customer Payment Overdue'){
    const invoiceDetails=readObject('dfab-invoice-details-v1');
    const balances=documentReportRows('Pending Receivables',['Invoice No','Customer','Invoice Amount','Received Amount','Balance Amount'],
      readDocuments,readObject);
    return balances.flatMap(([number,customer,billed,paid,balance])=>{
      const detail=invoiceDetails[number]?.form;
      const due=isoDate(detail?.dueDate);
      if(!due||due>=today)return [];
      const days=(Date.parse(today)-Date.parse(due))/86400000;
      return [row([number,customer,due,days,billed,paid,balance,detail?.currency],'Sales Invoice',number)];
    }).sort((a,b)=>b.values[3]-a.values[3]);
  }
  return [];
}

export function connectedOperations(module,reference,links,readDocuments,canRead){
  const related=[];
  const seen=new Set();
  const add=(page,number)=>{
    if(!hasDocumentValue(number)||!canRead(page))return;
    const key=JSON.stringify([page,normalizeReference(number)]);
    if(seen.has(key))return;
    const record=readDocuments(page).find(doc=>normalizeReference(doc.number)===normalizeReference(number));
    if(record){seen.add(key);related.push({module:page,reference:record.number,status:record.fields.Status||record.fields['QC Status']});}
  };
  for(const link of links){
    if(!link)continue;
    if(link.from===module&&normalizeReference(link.reference)===normalizeReference(reference))add(link.to,link.created);
    if(link.to===module&&normalizeReference(link.created)===normalizeReference(reference))add(link.from,link.reference);
  }
  const record=readDocuments(module).find(value=>normalizeReference(value.number)===normalizeReference(reference));
  if(record?.fetchedFrom)add(record.fetchedFrom.module,record.fetchedFrom.number);
  if(module==='Purchase Orders'&&canRead('GRN')){
    for(const received of readDocuments('GRN'))if(normalizeReference(received.fields['PO No'])===normalizeReference(reference))add('GRN',received.number);
  }
  if(module==='Sales Orders'){
    for(const page of ['Work Order','Delivery Challan','Sales Invoice']){
      if(!canRead(page))continue;
      for(const document of readDocuments(page)){
        const source=document.fields['SO No']||document.fields.sourceOrder;
        if(normalizeReference(source)===normalizeReference(reference))add(page,document.number);
      }
    }
  }
  if(module==='Route Cards')add('Work Order',record?.fields['WO No']);
  return related;
}
