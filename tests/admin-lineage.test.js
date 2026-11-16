import test from 'node:test';
import assert from 'node:assert/strict';
import {fieldTransfers, traceDocument, groupDocumentFields, configuredSourceValue} from '../src/admin-lineage.js';

const catalog=[
 {page:'Purchase Orders',module_group:'Purchase',columns:['PO No','Vendor','Amount','Status'],fields:['PO No','Vendor','Amount'],default_next:'GRN'},
 {page:'GRN',module_group:'Stores',columns:['GRN No','PO No','Vendor','Amount','Status'],fields:['GRN No','PO No','Vendor','Amount']},
];
test('Admin flow trace shows saved section, downstream form fields and source reports',()=>{
 const trace=traceDocument({page:'Purchase Orders',catalog,edges:[{source_page:'Purchase Orders',target_page:'GRN',field_map:{'PO No':'PO No'}}],storage:[],counts:{'dfab-erp-Purchase Orders':11},reports:{'Purchase Order Register':{source:'Purchase Orders'}}});
 assert.equal(trace.stores[0].count,11);
 assert.equal(trace.links[0].destination,'GRN');
 assert.deepEqual(trace.links[0].transfers.filter(f=>f.kind==='configured').map(f=>f.target),['PO No']);
 assert.deepEqual(trace.reports,['Purchase Order Register']);
});
test('Unconfigured transfer hints include only exact shared field names',()=>{
 const transfers=fieldTransfers(catalog[0],catalog[1]);
 assert.ok(transfers.some(item=>item.target==='Vendor'&&item.kind==='same-name'));
 assert.ok(!transfers.some(item=>item.target==='GRN No'));
 assert.ok(!transfers.some(item=>item.target==='Status'));
});
test('Detailed form groups preserve every original field exactly once',()=>{
 const fields=['PO No','Vendor','Item','Qty','Amount','Expected Date','Remarks'];
 assert.deepEqual(groupDocumentFields(fields).flatMap(section=>section.fields).sort(),[...fields].sort());
});
test('Configured field value returns even zero and leaves missing mappings untouched',()=>{
 assert.equal(configuredSourceValue({'Ordered Qty':0},'Received Qty',{'Received Qty':'Ordered Qty'}),0);
 assert.equal(configuredSourceValue({'Ordered Qty':3},'Received Qty',{}),undefined);
});

test('Admin traces existing legacy invoice storage without creating a new collection',()=>{
 const data=[...catalog,{page:'Sales Invoice',module_group:'Sales',columns:['Invoice No'],fields:['Invoice No']}];
 const trace=traceDocument({page:'Sales Invoice',catalog:data,edges:[],storage:[],counts:{'dfab-erp-sales-invoices-v2':84},reports:{}});
 assert.deepEqual(trace.stores,[{key:'dfab-erp-sales-invoices-v2',count:84}]);
});
