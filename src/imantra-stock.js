import { isoDate } from './erp-utils.js';
/** Derived operational stock view from confirmed document statuses. No writes or mutation. */
const num = value => {const n=Number(String(value??'').replaceAll(',',''));return Number.isFinite(n)?n:0};
const same = (a,b) => String(a??'').trim().toLowerCase()===String(b??'').trim().toLowerCase();
const specs = [
  {key:'Opening Stock',item:1,qty:3,status:5,allowed:['Posted'],direction:1,date:null,reference:0,rate:4},
  {key:'GRN',item:3,qty:4,status:5,allowed:['Accepted'],direction:1,date:null,reference:0},
  {key:'Material Issue',item:2,qty:3,status:5,allowed:['Issued'],direction:-1,date:null,reference:0},
  {key:'Return to Store',item:2,qty:3,status:6,allowed:['Posted'],direction:1,date:5,reference:0},
  {key:'Purchase Return',item:3,qty:4,status:6,allowed:['Returned'],direction:-1,date:null,reference:0},
  {key:'Excess Stock',item:1,qty:3,status:5,allowed:['Adjusted'],direction:1,date:null,reference:0},
  {key:'Shortage Stock',item:1,qty:3,status:5,allowed:['Adjusted'],direction:-1,date:null,reference:0},
  {key:'Production Output',item:2,qty:3,status:5,allowed:['Accepted'],direction:1,date:null,reference:0},
  {key:'Scrap Entry',item:2,qty:3,status:5,allowed:['Disposed'],direction:-1,date:null,reference:0},
  {key:'Route Cards',item:2,qty:4,status:5,allowed:['Accepted'],direction:1,date:null,reference:0,processOnly:true},
  {key:'Delivery Challan',item:3,qty:4,status:6,allowed:['Dispatched','Delivered'],direction:-1,date:null,reference:0,processOnly:true},
  {key:'Stock Adjustment',item:1,qty:3,status:6,allowed:['Posted'],direction:1,date:5,reference:0}
];
export const stockMovementSources=specs.map(rule=>rule.key);

export function postedStockMovements(readRows){
  const records=[];
  for(const rule of specs){
    for(const row of readRows(`dfab-erp-${rule.key}`)||[]){
      if(!Array.isArray(row)||!rule.allowed.includes(String(row[rule.status]||'')))continue;
      const extra=row.at(-1)?.version===1?row.at(-1):null;
      if(rule.processOnly&&!extra?.processVersion)continue;
      const lines=extra?.processVersion?extra.lines:null;
      if(lines?.length){
        for(const line of lines){
          const qty=num(line.quantity)*rule.direction*(rule.key==='Stock Adjustment'&&extra.header?.['Adjustment direction']==='Decrease'?-1:1),item=String(line.code||line.description||'').trim();
          if(item&&qty)records.push({item,description:line.description,uom:line.uom,qty,source:rule.key,reference:String(row[rule.reference]??''),date:isoDate(extra.header?.Date),rate:num(line.rate)>0?num(line.rate):null});
        }
      }else{
        const qty=num(row[rule.qty])*rule.direction,item=String(row[rule.item]??'').trim();
        if(!item||item==='-'||!qty)continue;
        records.push({item,qty,source:rule.key,reference:String(row[rule.reference]??''),date:isoDate(rule.date===null?extra?.header?.Date:row[rule.date]),rate:rule.rate===undefined?null:num(row[rule.rate])});
      }
    }
  }
  return records;
}
export function stockBalances(movements){
  const map=new Map();
  for(const move of movements){
    const key=move.item.toLowerCase();const previous=map.get(key)||{item:move.item,inward:0,outward:0,closing:0,rate:null,lastDate:''};
    if(move.qty>0)previous.inward+=move.qty;else previous.outward+=-move.qty;
    previous.closing+=move.qty;
    if(move.rate!==null && move.rate>0)previous.rate=move.rate;
    if(move.date && move.date>previous.lastDate)previous.lastDate=move.date;
    map.set(key,previous);
  }
  return [...map.values()].sort((a,b)=>a.item.localeCompare(b.item));
}
/** Compare the proposed document collection with the saved operational stock view. */
export function validateStockChange(title,before,after,readRows) {
  if(!specs.some(rule=>rule.key===title))return null;
  const key=`dfab-erp-${title}`;
  const balances=rows=>stockBalances(postedStockMovements(section=>section===key?rows:readRows(section)));
  const prior=new Map(balances(before).map(row=>[row.item.toLowerCase(),row.closing]));
  const negative=balances(after).find(row=>row.closing < -1e-8 && row.closing < (prior.get(row.item.toLowerCase())??0)-1e-8);
  return negative?`${title} would reduce posted stock for ${negative.item} below zero (${negative.closing}).`:null;
}

const rangedReports=new Set(['Regular Stock List','Stock Ledger','Stock Report','Groupwise Stock Report']);
export const isRangedStockReport=name=>rangedReports.has(name);

export function stockReportRows(name,columns,readRows,details,parameters) {
  if(!isRangedStockReport(name)&&name!=='Product Rack List')return null;
  const products=new Map();
  for(const [code,description,type,group,uom] of readRows('dfab-erp-products-v3').filter(Array.isArray)){
    const product={code,description,type,group,uom,rack:details[code]?.rack};
    if(code)products.set(String(code).trim().toLowerCase(),product);
  }
  const byDescription=new Map();
  for(const product of products.values()){
    const key=String(product.description??'').trim().toLowerCase();
    byDescription.set(key,byDescription.has(key)?null:product);
  }
  const from=isoDate(parameters.fromDate);
  const to=isoDate(parameters.asOnDate||parameters.toDate);
  const dated=from||to;
  const grouped=new Map();
  for(const move of postedStockMovements(readRows)){
    const key=move.item.toLowerCase();
    const product=products.get(key)||byDescription.get(key);
    const identity=String(product?.code??move.item).toLowerCase();
    if(!grouped.has(identity))grouped.set(identity,[]);
    grouped.get(identity).push(move);
  }
  const allItems=new Set([...products.keys(),...grouped.keys()]);
  const project=fields=>columns.map(column=>fields[column]??'-');
  return [...allItems].sort((a,b)=>a.localeCompare(b)).flatMap(key=>{
    const movements=grouped.get(key)||[];
    const product=products.get(key);
    const identity={'Product Code':product?.code??movements[0]?.item,Description:product?.description||movements.find(m=>m.description)?.description,
      'Product Description':product?.description||movements.find(m=>m.description)?.description,'Product Type':product?.type,Group:product?.group,
      UOM:product?.uom||movements.find(m=>m.uom)?.uom,Rack:product?.rack,'Rack Location':product?.rack};
    const undated=movements.some(move=>!move.date);
    const visible=movements.filter(move=>!dated||(move.date&&(!to||move.date<=to)))
      .sort((a,b)=>a.date.localeCompare(b.date));
    let opening=0,inward=0,outward=0,balance=0,rate=null,fullyCosted=true;
    const ledger=[];
    for(const move of visible){
      balance+=move.qty;
      if(move.qty>0){
        if(move.rate===null||move.rate<=0||(rate!==null&&rate!==move.rate))fullyCosted=false;
        if(move.rate!==null&&move.rate>0)rate=move.rate;
      }
      if(from&&move.date<from){
        opening+=move.qty;
        continue;
      }
      const added=Math.max(0,move.qty),removed=Math.max(0,-move.qty);
      inward+=added;
      outward+=removed;
      if(name==='Stock Ledger')ledger.push(project({...identity,Date:move.date||undefined,
        'Transaction Type':move.source,'Reference No':move.reference,Inward:added,Outward:removed,
        Balance:undated?undefined:balance}));
    }
    if(name==='Stock Ledger')return ledger;
    const closing=dated&&undated?undefined:balance;
    if(name==='Regular Stock List'||name==='Product Rack List')return [project({...identity,'Available Stock':closing})];
    if(!visible.length&&!undated)return [];
    return [project({...identity,Opening:undated?undefined:opening,'Opening Stock':undated?undefined:opening,
      Inward:inward,Outward:outward,'Inward Qty':inward,'Outward Qty':outward,
      Closing:closing,'Closing Stock':closing,Value:closing!==undefined&&fullyCosted&&rate!==null?Math.round(closing*rate*100)/100:undefined})];
  });
}
