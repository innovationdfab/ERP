import {isoDate} from './erp-utils.js';
const text=value=>value==null?'':Array.isArray(value)?value.map(text).join(' '):typeof value==='object'?Object.values(value).map(text).join(' '):String(value);
export const searchText=value=>text(value).normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/\s+/g,' ').trim();
export function matchesSearch(value,query){const haystack=searchText(value);return searchText(query).split(' ').filter(Boolean).every(term=>haystack.includes(term));}
export function dateRangeIssue(from,to){if(from&&!isoDate(from)||to&&!isoDate(to))return 'Enter a valid filter date.';return from&&to&&isoDate(from)>isoDate(to)?'From date must be on or before To date.':'';}
export function withinDateRange(date,from='',to=''){if(dateRangeIssue(from,to))return false;if(!from&&!to)return true;const value=isoDate(date);return !!value&&(!from||value>=isoDate(from))&&(!to||value<=isoDate(to));}
export function reportParameterMatches(reportKey,columns,row,param,value){
 const term=searchText(String(value??'').replace(/^--|--$/g,''));if(!term||term==='all')return true;
 if(param.kind==='date'){
  if(['Regular Stock List','Stock Ledger','Stock Report','Groupwise Stock Report','Product Rack List','Stock List','Stock Valuation','Inventory Ageing'].includes(reportKey))return true;
  const index=columns.findIndex(c=>/^(date|.* date|date of .*|last movement)$/i.test(c));if(index<0)return true;
  const date=isoDate(row[index]),bound=isoDate(value);if(!date||!bound)return false;
  if(/from|start/i.test(param.key))return date>=bound;
  if(/toDate|end|asOn/i.test(param.key))return date<=bound;
  return date===bound;
 }
 const aliases={product:['Product Code','Product Description','Product','Product / Service','Description','Item'],customer:['Customer','Customer Name','Party'],vendor:['Vendor','Vendor Name','Supplier'],group:['Group','Product Group'],user:['User','User Name','Owner']};
 const indices=columns.flatMap((c,i)=>(aliases[param.key]||[]).includes(c)?[i]:[]);
 if(param.key==='fromProduct'||param.key==='toProduct'){const i=columns.findIndex(c=>aliases.product.includes(c));if(i<0)return true;const sort=searchText(row[i]).localeCompare(term,undefined,{numeric:true});return param.key==='fromProduct'?sort>=0:sort<=0;}
 return matchesSearch(indices.length?indices.map(i=>row[i]):row,term);
}
