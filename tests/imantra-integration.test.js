import test from 'node:test';
import assert from 'node:assert/strict';
import {imantraTransactions, imantraReportDefinitions,imantraReportRows,validateImantraDocument} from '../src/imantra-integration.js';
import {postedStockMovements,stockBalances,validateStockChange} from '../src/imantra-stock.js';
test('all integrated modules have unique fields, matching status, and a document key',()=>{
  for(const [name,def] of Object.entries(imantraTransactions)){
    assert.ok(name);assert.ok(def.columns.length>=4);assert.equal(def.columns.at(-1),'Status');
    assert.equal(new Set(def.columns).size,def.columns.length);assert.ok(def.statuses.length>=2);
    assert.equal(def.fields.length,def.columns.length-1);
  }
});
test('integrated reports use declared source data only, never fake rows',()=>{
  const configs={'Purchase Orders':{columns:['PO No','Vendor','PO Date','Amount','Delivery Date','Status']}};
  const read=key=>key==='dfab-erp-Purchase Orders'?[['PO/1','Vendor 1','2026-11-10','120','2026-11-14','Received'],['PO/2','Vendor 2','2026-11-11','150','2026-11-15','Draft']]:[];
  assert.deepEqual(imantraReportRows('Executed Purchase Order Register',read,configs),[['PO/1','Vendor 1','120','2026-11-14','Received']]);
  assert.equal(imantraReportRows('Missing Report',read,configs),null);
  assert.ok(Object.keys(imantraReportDefinitions).length>=20);
});
test('new document validation rejects missing required fields, invalid qty and missing source',()=>{
  const v={ 'Schedule No':'PS1','PO No':'PO/1',Vendor:'A',Item:'Steel',Qty:'-2','Planned Date':'2026-11-15' };
  assert.match(validateImantraDocument('Procurement Schedule',v,()=>({})),/Qty/);
  v.Qty='5';assert.match(validateImantraDocument('Procurement Schedule',v,()=>null),/does not exist/);
  assert.equal(validateImantraDocument('Procurement Schedule',v,()=>({})),null);
});
test('issued and accepted movements are counted; drafts never affect stock',()=>{
  const rows={
    'dfab-erp-Opening Stock':[['OP1','Steel','MAIN','100','25','Posted'],['OP2','Steel','MAIN','1000','25','Draft']],
    'dfab-erp-Material Issue':[['MI1','WO1','Steel','30','MAIN','Issued'],['MI2','WO1','Steel','100','MAIN','Draft']],
    'dfab-erp-Return to Store':[['RS1','WO1','Steel','5','MAIN','2026-11-14','Posted']],
  };
  const get=k=>rows[k]||[];
  const movement=postedStockMovements(get);
  assert.equal(movement.length,3);
  assert.equal(stockBalances(movement)[0].closing,75);
  const issues=get('dfab-erp-Material Issue');
  assert.match(validateStockChange('Material Issue',issues,[...issues,['MI3','WO1','Steel','76','MAIN','Issued']],get),/below zero/);
  assert.equal(validateStockChange('Material Issue',issues,[...issues,['MI3','WO1','Steel','75','MAIN','Issued']],get),null);
  assert.match(validateStockChange('Opening Stock',get('dfab-erp-Opening Stock'),[],get),/below zero/);
  assert.match(validateStockChange('Stock Adjustment',[],[['ADJ-1','Unstocked','MAIN','-2','Correction','2026-11-20','Posted']],get),/below zero/);
});

test('planning to purchase indent copies real quantities and dates without approval', async()=>{
  const {imantraForwardPrefill}=await import('../src/imantra-integration.js');
  const source={Item:'SS304','Required Qty':'28','Need Date':'2026-11-20',Department:'Fabrication'};
  assert.deepEqual(imantraForwardPrefill('Procurement Planning','Purchase Indents',source),{Item:'SS304',Qty:'28','Required Date':'2026-11-20',Department:'Fabrication'});
  assert.equal(imantraForwardPrefill('Procurement Schedule','GRN',{'PO No':'PO1',Vendor:'V1',Item:'SS304'})['Received Qty'],'');
});
