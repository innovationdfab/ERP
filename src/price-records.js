import {isoDate} from './erp-utils.js';

export const priceStorageKey=mode=>`dfab-erp-${mode}-price-records-v1`;

export function validatePrice({party,product,uom,rate,from,until}) {
  if(!party?.trim()||!product?.trim()||!uom?.trim())return 'Party, product and UOM are required.';
  if(!/^\d+(?:\.\d+)?$/.test(String(rate??'').trim())||!Number.isFinite(Number(rate)))return 'Enter a valid non-negative rate.';
  if(!isoDate(from)||until&&!isoDate(until))return 'Enter valid effective dates.';
  if(until&&isoDate(until)<isoDate(from))return 'Effective To must be on or after Effective From.';
  return '';
}

export function readPriceRecords(mode,snapshot,products,parties) {
  const records=Array.isArray(snapshot[priceStorageKey(mode)])?[...snapshot[priceStorageKey(mode)]]:[];
  const productCodes=new Set(products.map(([code])=>code));
  const partyCodes=new Set(parties.map(([code])=>code));
  const prefix=`dfab-live-${mode}-prices-`;
  for(const [key,rows] of Object.entries(snapshot)){
    if(!key.startsWith(prefix)||!Array.isArray(rows))continue;
    const reference=key.slice(prefix.length);
    for(const [index,row] of rows.entries()){
      if(!Array.isArray(row))continue;
      const code=`legacy:${key}:${index}`;
      if(mode==='process'){
        const [party,product,uom,rate,from,status]=row;
        records.push({code,process:reference,party,product,uom,rate,from,status});
      }else if(productCodes.has(reference)&&!partyCodes.has(reference)){
        const [party,uom,rate,from,until,status]=row;
        records.push({code,product:reference,party,uom,rate,from,until,status});
      }else if(partyCodes.has(reference)&&!productCodes.has(reference)){
        const [product,description,uom,rate,from,status]=row;
        records.push({code,party:reference,product,description,uom,rate,from,status});
      }
    }
  }
  return records.filter(record=>record?.product&&record?.party);
}
