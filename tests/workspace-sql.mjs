// Fresh in-memory PostgreSQL only. Install/link @electric-sql/pglite or set ERP_PGLITE_DIR.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {join} from 'node:path';

const directory=process.env.ERP_PGLITE_DIR;
const {PGlite}=await import(directory?pathToFileURL(join(directory,'index.js')).href:'@electric-sql/pglite');
const {pgcrypto}=await import(directory?pathToFileURL(join(directory,'contrib/pgcrypto.js')).href:'@electric-sql/pglite/contrib/pgcrypto');
const db=new PGlite({extensions:{pgcrypto}});
const admin='11111111-1111-1111-1111-111111111111';
const staff='22222222-2222-2222-2222-222222222222';
try{
  await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth;
  create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
  grant usage on schema auth to anon,authenticated,service_role;
  insert into auth.users(id,email) values('${admin}','qa-admin@example.test');`);
  for(const migration of [
    'DFAB_ERP_PRODUCTION','ERP_FLOW_INTEGRITY_UPGRADE','ERP_PRODUCTION_GUARDRAILS','ERP_ADMIN_CONTROL',
    'ERP_ADMIN_OPERATIONS_V2','ERP_INITIAL_LOGIN_PASSWORD_POLICY','ERP_WORKSPACE_INTEGRITY'
  ]){
    await db.exec(readFileSync(new URL(`../supabase/${migration}.sql`,import.meta.url),'utf8'));
    console.log('Applied',migration);
  }
  await db.exec(readFileSync(new URL('../supabase/ERP_WORKSPACE_INTEGRITY.sql',import.meta.url),'utf8'));
  await db.exec(`insert into auth.users(id,email) values('${staff}','qa-staff@example.test');`);
  const asUser=async id=>{
    await db.exec('reset role;');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
    await db.exec('set role authenticated;');
  };
  const save=(key,expected,payload)=>db.query('select erp_put_ui_state_if_unchanged($1,$2,$3)',[key,
    expected===null?null:JSON.stringify(expected),JSON.stringify(payload)]);
  const batch=changes=>db.query('select erp_commit_ui_state_batch($1::jsonb)',[JSON.stringify(changes)]);
  const snapshot=async()=>new Map((await db.query('select * from erp_get_ui_state()')).rows.map(row=>[row.storage_key,row.payload]));
  await asUser(admin);
  const role=(await db.query('select erp_admin_save_role(null,$1,$2,$3,true,$4::jsonb) as id',
    ['QA_STAFF','QA staff','Isolated test',JSON.stringify([
      {page:'Sales Enquiries',view:true,edit:true},
      {page:'Sales Quotations',view:true,create:true,edit:true},
      {page:'Products',view:true,create:true},
      {page:'Job Work Inward',view:true},
      {page:'Inward QC',view:true,create:true,edit:true,approve:true},
      {page:'Sales Orders',view:true,create:true},
      {page:'Job Work Return DC',view:true},
      {page:'Sales Invoice',view:true,create:true},
      {page:'Department Master',view:true,create:true,edit:true},
      {page:'Activity Log',view:true},{page:'User Wise Transactions List',view:true}
    ])])).rows[0].id;
  await db.query('select erp_admin_save_user($1,null,$2,true,$3::uuid[])',[staff,'QA Staff',[role]]);
  const enquiries=[['ENQ-1','QA Customer','Steel','2','2026-11-17','New']];
  await save('dfab-erp-Sales Enquiries',null,enquiries);
  await save('dfab-erp-Job Work Inward',null,[['JOB-1','QA Customer','DC-1','Steel','2','Received']]);
  await save('dfab-erp-Job Work Return DC',null,[
    ['JOB-RETURN-READY','QA Customer','JOB-1','Steel','2','Dispatched'],
    ['JOB-RETURN-DRAFT','QA Customer','JOB-1','Steel','2','Draft']
  ]);
  await save('dfab-erp-vendors-v2',null,[['SECRET-VENDOR','Restricted vendor']]);
  await asUser(staff);
  assert.equal((await snapshot()).has('dfab-erp-vendors-v2'),false);
  const changed=[['ENQ-1','QA Updated','Steel','2','2026-11-17','New']];
  await save('dfab-erp-Sales Enquiries',enquiries,changed);
  await assert.rejects(save('dfab-erp-Sales Enquiries',enquiries,changed),error=>error.code==='40001');
  const quotations=[['SQ-1','QA Updated','ENQ-1','100','Draft']];
  await assert.rejects(save('dfab-erp-Sales Quotations',null,[['SQ-1','QA Updated','ENQ-1','100','Accepted']]),error=>error.code==='42501');
  const link={from:'Sales Enquiries',to:'Sales Quotations',reference:'ENQ-1',created:'SQ-1'};
  await assert.rejects(batch([
    {key:'dfab-erp-Sales Enquiries',expected:changed,payload:changed},
    {key:'dfab-workflow-links-v1',expected:null,payload:[link]}
  ]),/must create exactly/);
  assert.equal((await snapshot()).has('dfab-workflow-links-v1'),false);
  await batch([
    {key:'dfab-erp-Sales Quotations',expected:null,payload:quotations},
    {key:'dfab-workflow-links-v1',expected:null,payload:[link]}
  ]);
  const jobInspectionKey='dfab-erp-Inward QC';
  const jobInspection=[['QC-1','','Steel','2','Inspector','Pending',{version:1,header:{'Job Inward No':'JOB-1'}}]];
  const jobLink={from:'Job Work Inward',to:'Inward QC',reference:'JOB-1',created:'QC-1'};
  const orderLink={from:'Inward QC',to:'Sales Orders',reference:'QC-1',created:'SO-JOB-1'};
  const linkKey='dfab-workflow-links-v1';
  await batch([{key:jobInspectionKey,expected:null,payload:jobInspection},{key:linkKey,expected:[link],payload:[link,jobLink]}]);
  const jobOrder=[
    {key:'dfab-erp-Sales Orders',expected:null,payload:[['SO-JOB-1','QA Customer','PO-1','Steel','2','2026-11-17','Draft']]},
    {key:linkKey,expected:[link,jobLink],payload:[link,jobLink,orderLink]}
  ];
  await assert.rejects(batch(jobOrder),/approval gate/);
  const passedInspection=jobInspection.map(row=>row.map((value,index)=>index===5?'Passed':value));
  await save(jobInspectionKey,jobInspection,passedInspection);
  await batch(jobOrder);
  assert.deepEqual((await snapshot()).get(linkKey),[link,jobLink,orderLink]);
  const returnInvoice=reference=>[
    {key:'dfab-erp-sales-invoices-v2',expected:null,payload:[['1','SI-JOB-1','17-Nov-2026','QA Customer','PO-1','-','DRAFT','0']]},
    {key:linkKey,expected:[link,jobLink,orderLink],payload:[link,jobLink,orderLink,
      {from:'Job Work Return DC',to:'Sales Invoice',reference,created:'SI-JOB-1'}]}
  ];
  await assert.rejects(batch(returnInvoice('JOB-RETURN-DRAFT')),/approval gate/);
  await batch(returnInvoice('JOB-RETURN-READY'));
  assert.equal((await snapshot()).get('dfab-erp-sales-invoices-v2')[0][1],'SI-JOB-1');

  const submitted=[['SQ-2','QA Updated','ENQ-1','100','Approval Pending'],...quotations];
  await save('dfab-erp-Sales Quotations',quotations,submitted);
  const pendingBoth=[submitted[0],[...quotations[0].slice(0,4),'Approval Pending']];
  await save('dfab-erp-Sales Quotations',submitted,pendingBoth);
  await assert.rejects(save('dfab-erp-Sales Quotations',pendingBoth,[pendingBoth[0],[...quotations[0].slice(0,4),'Approved']]),error=>error.code==='42501');
  await assert.rejects(save('dfab-erp-Sales Quotations',pendingBoth,[['SQ-3','QA Updated','ENQ-1','300','Approved'],...pendingBoth]),error=>error.code==='42501');
  await save('dfab-live-departments',null,['Stores']);
  await save('dfab-live-departments',['Stores'],['Stores','QA']);
  const product=[['QA-P1','QA Steel','FINISHED GOOD','FABRICATION','NOS','R01','DRAFT']];
  const parts=[
    {key:'dfab-erp-products-v3',expected:null,payload:product},
    {key:'dfab-erp-products-details-v1',expected:null,payload:{'QA-P1':{description:'QA Steel'}}}
  ];
  await assert.rejects(batch([parts[0],{...parts[1],expected:{unexpected:true}}]),error=>error.code==='40001');
  assert.equal((await snapshot()).has(parts[0].key),false);
  await batch(parts);
  const saved=await snapshot();
  assert.deepEqual(saved.get(parts[0].key),product);
  assert.deepEqual(saved.get(parts[1].key),parts[1].payload);
  const activity=(await db.query('select * from erp_workspace_activity()')).rows;
  assert.ok(activity.some(event=>event.reference===parts[0].key));
  assert.ok(!activity.some(event=>event.module==='Vendors'));
  assert.ok(activity.every(event=>!Object.hasOwn(event,'new_data')));
  const history=(await db.query("select * from erp_workspace_transactions((now() at time zone 'Asia/Kolkata')::date)")).rows;
  assert.ok(history.some(event=>event.reference==='ENQ-1'&&event.operation==='Updated'));
  assert.ok(history.some(event=>event.reference==='SQ-2'&&event.status==='Approval Pending'));
  assert.ok(!history.some(event=>event.reference==='SECRET-VENDOR'));
  const restore=changes=>db.query('select erp_restore_ui_state($1::jsonb)',[JSON.stringify(changes)]);
  const settings={key:'dfab-workspace-settings',expected:null,payload:{company:'QA'}};
  await assert.rejects(restore([settings]),error=>error.code==='42501');
  await asUser(admin);
  await assert.rejects(restore([settings,{key:'dfab-zz-secret-token',expected:null,payload:{}}]),/Unsupported backup key/);
  assert.equal((await snapshot()).has(settings.key),false);
  await restore([settings]);
  assert.deepEqual((await snapshot()).get(settings.key),settings.payload);
  await asUser(staff);
  await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({app_metadata:{erp_initial_password_pending:true}})]);
  assert.equal((await snapshot()).size,0);
  console.log('Verified staff edit and create rights, approvals, atomic handoff and rollback, job-work branching, hidden data, activity scope, transactional restore and initial-password enforcement.');
}finally{
  await db.close();
}
