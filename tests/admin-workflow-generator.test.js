import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import catalog from '../src/admin-catalog.json' with {type:'json'};
import {generateRegisteredFlows,inferSafeFieldMap,normalizeWorkflowCatalog} from '../src/admin-workflow-generator.js';
import {validateTemplateEdges} from '../src/admin-permissions.js';

const fullCatalog=normalizeWorkflowCatalog(catalog);
test('automatic builder creates every registered document-to-document link, not unrelated masters or reports',()=>{
 const result=generateRegisteredFlows(catalog);
 assert.equal(result.error,'');
 assert.equal(result.skipped.length,0);
 assert.equal(result.totalDefined,40);
 assert.equal(result.edges.length,40);
 assert.ok(!result.edges.some(e=>e.source_page==='Stock Report'));
 assert.equal(validateTemplateEdges(result.edges,fullCatalog),'');
 assert.ok(result.groups.includes('Production'));
 assert.ok(result.groups.includes('Purchase'));
 assert.ok(result.groups.includes('Sales'));
});
test('auto map only uses existing source and destination column names and omits output calculations',()=>{
 const result=generateRegisteredFlows(catalog);
 const dict=new Map(fullCatalog.map(e=>[e.name,e]));
 for(const edge of result.edges){
  const src=dict.get(edge.source_page),dest=dict.get(edge.target_page);
  for(const [to,from] of Object.entries(edge.field_map)){
   assert.ok(src.columns.includes(from),`${edge.source_page} lacks ${from}`);
   assert.ok(dest.fields.includes(to),`${edge.target_page} lacks ${to}`);
   assert.notEqual(to,dest.columns[0],`Must not overwrite generated document ID for ${dest.name}`);
  }
  assert.ok(!Object.hasOwn(edge.field_map,'Status'));
  assert.ok(!Object.hasOwn(edge.field_map,'Good Qty'));
  assert.ok(!Object.hasOwn(edge.field_map,'Reject Qty'));
 }
 const sales=result.edges.find(e=>e.source_page==='Sales Enquiries');
 assert.equal(sales.field_map.Enquiry,'Enquiry No');
 const order=result.edges.find(e=>e.source_page==='Purchase Orders');
 assert.equal(order.field_map['PO No'],'PO No');
 const vendor=result.edges.find(e=>e.source_page==='Purchase');
 assert.equal(vendor.field_map.Invoice,'Invoice No');
});
test('automatic workflow builder keeps valid server gate statuses and blocks invalid catalog entries',()=>{
 const a=[{page:'Example',module_group:'Sales',columns:['No','Status','Customer'],fields:['No','Customer'],statuses:['Draft','Approved'],default_next:'Next',default_gate_statuses:['Approved']},
  {page:'Next',columns:['No','Customer','Status'],fields:['No','Customer'],statuses:['Draft']}];
 const result=generateRegisteredFlows(a);
 assert.deepEqual(result.edges[0].gate_statuses,['Approved']);
 assert.deepEqual(result.edges[0].field_map,{Customer:'Customer'});
 const bad=generateRegisteredFlows([{...a[0],default_gate_statuses:['Drafted']},a[1]]);
 assert.equal(bad.edges.length,0);
 assert.equal(bad.skipped.length,1);
 assert.equal(bad.totalDefined,1);
});
test('automatic builder never invents routes or assigns sensitive financial/production values',()=>{
 assert.deepEqual(generateRegisteredFlows([{name:'Independent',fields:['ID'],columns:['ID']}]).edges,[]);
 const from={name:'Source',columns:['ID','Status','Amount','Good Qty','Qty','Product'],fields:[]};
 const to={name:'Dest',columns:['NextID','Status','Amount','Good Qty','Qty','Product'],fields:['NextID','Amount','Good Qty','Qty','Product']};
 assert.deepEqual(inferSafeFieldMap(from,to),{Qty:'Qty',Product:'Product'});
});
test('Admin section is only in the topbar, not duplicated in the sidebar',()=>{
 const jsx=fs.readFileSync(path.join(process.cwd(),'src/main.jsx'),'utf8');
 assert.match(jsx,/erp-top-admin-btn/);
 assert.ok(jsx.indexOf('erp-top-admin-btn')<jsx.indexOf('global-search'));
 assert.doesNotMatch(jsx,/className=\{`nav-tree-item admin-launch/);
});
test('Admin generated template uses existing secure draft/save/publish RPC paths and reflects through runtime reload',()=>{
 const jsx=fs.readFileSync(path.join(process.cwd(),'src/admin-control.jsx'),'utf8');
 const shell=fs.readFileSync(path.join(process.cwd(),'src/main.jsx'),'utf8');
 assert.match(jsx,/generateRegisteredFlows\(data\?\.catalog\|\|\[\]\)/);
 assert.match(jsx,/Generate all flows/);
 assert.match(jsx,/saveTemplate\(/);
 assert.match(jsx,/publishTemplate\(/);
 assert.match(jsx,/onWorkflowPublished\(\)/);
 assert.match(shell,/refreshActiveWorkflow=async/);
 assert.match(shell,/window.addEventListener\('focus',sync\)/);
 assert.match(shell,/workflowOverride\?\.field_map/);
});
