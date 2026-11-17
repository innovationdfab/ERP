import test from 'node:test';
import assert from 'node:assert/strict';
import {priceStorageKey,readPriceRecords,validatePrice} from '../src/price-records.js';

test('product-wise and party-wise history resolve to the same price record format',()=>{
  const products=[['P1','Steel']];
  const vendors=[['V1','Vendor']];
  const saved={code:'new',product:'P1',party:'V1',rate:2.50,uom:'KG',from:'2026-11-17'};
  const records=readPriceRecords('vendor',{
    [priceStorageKey('vendor')]:[saved],
    'dfab-live-vendor-prices-P1':[['V1','KG','3.00','16-Nov-2026','17-Nov-2026','ACTIVE']],
    'dfab-live-vendor-prices-V1':[['P1','Steel','KG','4.00','17-Nov-2026','ACTIVE']]
  },products,vendors);
  assert.equal(records.length,3);
  assert.ok(records.every(record=>record.product==='P1'&&record.party==='V1'));
  assert.equal(records[0],saved);
});

test('prices reject negative rates and backwards ranges',()=>{
  const form={party:'V1',product:'P1',rate:'0.50',uom:'KG',from:'2026-11-17',until:'2026-12-01'};
  assert.equal(validatePrice(form),'');
  assert.match(validatePrice({...form,rate:'-1'}),/non-negative/);
  assert.match(validatePrice({...form,until:'2026-11-16'}),/after Effective From/);
});
