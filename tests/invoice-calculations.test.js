import test from 'node:test';
import assert from 'node:assert/strict';
import {calculateInvoice} from '../src/invoice-calculations.js';

test('invoice has correct taxable, tax and payable totals',()=>{
  const result=calculateInvoice([{description:'Steel',quantity:'3',rate:'150.00'},{description:'Cutting',quantity:'2',rate:'50'}],'18');
  assert.equal(result.taxable,550);assert.equal(result.tax,99);assert.equal(result.total,649);
  assert.equal(result.details.reduce((sum,line)=>sum+line.gross,0),649);
});
test('invoice line rounding is consistent and total equals rounded line totals',()=>{
  const result=calculateInvoice([{description:'Part',quantity:'3',rate:'0.335'},{description:'Other',quantity:'1',rate:'0.335'}],'18');
  assert.equal(result.details.reduce((sum,line)=>sum+Math.round(line.gross*100),0),Math.round(result.total*100));
});
test('invoice rejects zero quantities, missing description, negative rates and invalid tax',()=>{
  for(const lines of [[{description:'A',quantity:'0',rate:'10'}],[{description:'',quantity:'1',rate:'10'}],[{description:'A',quantity:'1',rate:'-1'}]])assert.throws(()=>calculateInvoice(lines,'18'));
  assert.throws(()=>calculateInvoice([{description:'A',quantity:'1',rate:'10'}],'101'));
  assert.throws(()=>calculateInvoice([{description:'A',quantity:'1',rate:'10'}],'foo'));
});
