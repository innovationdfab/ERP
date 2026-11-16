import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {canAccess,validateTemplateEdges,normalizedEdges} from '../src/admin-permissions.js';
import catalog from '../src/admin-catalog.json' with {type:'json'};

const finance = {name:'Vendor Payments',columns:['Payment No','Invoice','Vendor','Amount'],fields:['Payment No','Invoice','Vendor','Amount']};
const buying = {name:'Purchase Orders',columns:['PO No','Vendor','Amount'],fields:['PO No','Vendor','Amount']};
const invoice = {name:'Purchase',columns:['Invoice No','Vendor','PO No','Amount'],fields:['Invoice No','Vendor','PO No','Amount']};
const stages=[buying,invoice,finance];

const viewer={is_admin:false,rights:{'Purchase Orders':{view:true,create:false,edit:false,delete:false,approve:false,export:true}}};
test('role rights cannot grant an unassigned operation',()=>{
 assert.equal(canAccess(viewer,'Purchase Orders','view'),true);
 assert.equal(canAccess(viewer,'Purchase Orders','create'),false);
 assert.equal(canAccess(viewer,'Purchase Orders','approve'),false);
 assert.equal(canAccess(viewer,'Vendor Payments','view'),false);
 assert.equal(canAccess(viewer,'Purchase Orders','drop'),false);
 assert.equal(canAccess(null,'Purchase Orders','view'),false);
});
test('system admin can manage any module and permission',()=>{
 for(const action of ['view','create','edit','delete','approve','export'])assert.equal(canAccess({is_admin:true},'Vendor Payments',action),true);
});
test('authenticated staff may view safe read-only app pages',()=>{
 for(const page of ['Home','Workflow Guide','Change Password'])assert.equal(canAccess(viewer,page,'view'),true);
 assert.equal(canAccess(viewer,'Admin Control','view'),false);
 assert.equal(canAccess(viewer,'Home','edit'),false);
});
test('valid workflow template uses actual source and destination fields',()=>{
 const edges=[{source_page:'Purchase Orders',target_page:'Purchase',field_map:{'PO No':'PO No','Vendor':'Vendor'},gate_statuses:['Approved']}];
 assert.equal(validateTemplateEdges(edges,stages),'');
});
test('workflow editor blocks duplicate source, cycles and self links',()=>{
 assert.match(validateTemplateEdges([{source_page:'Purchase Orders',target_page:'Purchase'},{source_page:'Purchase Orders',target_page:'Vendor Payments'}],stages),/only one next step/i);
 assert.match(validateTemplateEdges([{source_page:'Purchase Orders',target_page:'Purchase'},{source_page:'Purchase',target_page:'Purchase Orders'}],stages),/cycle/i);
 assert.match(validateTemplateEdges([{source_page:'Purchase',target_page:'Purchase'}],stages),/Invalid workflow/i);
});
test('workflow editor rejects mappings using missing fields',()=>{
 assert.match(validateTemplateEdges([{source_page:'Purchase Orders',target_page:'Purchase',field_map:{'Invoice No':'Unknown Source'}}],stages),/Invalid workflow/i);
 assert.match(validateTemplateEdges([{source_page:'Purchase Orders',target_page:'Purchase',field_map:{'Unknown Target':'Vendor'}}],stages),/Invalid workflow/i);
});
test('workflow normalization removes invalid gate values without mutating source',()=>{
 const x=[{source_page:'Purchase Orders',target_page:'Purchase',gate_statuses:['Approved','',null],field_map:{Vendor:'Vendor'}}];
 const y=normalizedEdges(x);
 assert.deepEqual(y[0].gate_statuses,['Approved']);assert.equal(x[0].gate_statuses.length,3);
});
test('admin catalog includes the material, production, quality, sales, procurement and financial modules',()=>{
 const titles=new Set(catalog.map(c=>c.name));
 for(const page of ['Purchase Indents','Purchase Orders','GRN','Inward QC','Material Issue','Work Order','Production Output','Outward QC','Delivery Challan','Sales Invoice','Vendor Payments','Customer Payments','Users','User Roles'])assert.ok(titles.has(page),`missing ${page}`);
 assert.equal(titles.size,catalog.length,'duplicate page names');
});
test('admin SQL requires authenticated organization roles and checked workflow commits',()=>{
 const sql=fs.readFileSync(path.join(process.cwd(),'supabase/ERP_ADMIN_CONTROL.sql'),'utf8');
 assert.match(sql,/create or replace function public\.erp_admin_is_admin\(\)/i);
 assert.match(sql,/where ur\.user_id=auth\.uid\(\)/i);
 assert.match(sql,/status='published'/i);
 assert.match(sql,/erp_admin_can_page\(v_to,'create'\)/i);
 assert.match(sql,/default_gate_statuses/i);
 assert.match(sql,/erp\.verified_batch/i);
 assert.match(sql,/revoke execute on function public\.erp_put_ui_state\(text,jsonb\)/i);
 assert.match(sql,/create or replace function public\.erp_commit_ui_state_batch/i);
});
test('admin invite service verifies signed-in administrator before service account actions',()=>{
 const ts=fs.readFileSync(path.join(process.cwd(),'supabase/functions/erp-admin-invite/index.ts'),'utf8');
 assert.match(ts,/caller\.auth\.getUser\(jwt\)/);
 assert.match(ts,/caller\.rpc\('erp_admin_is_admin'\)/);
 assert.ok(ts.indexOf("caller.rpc('erp_admin_is_admin'") < ts.indexOf('await elevated.auth.admin.createUser('));
 assert.match(ts,/actor\.app_metadata\?\.\[initialFlag\] !== true/);
 assert.match(ts,/ERP_ALLOWED_ORIGINS/);
});
