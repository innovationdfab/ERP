import {freshDocument} from '../src/process-store.js';
import {projectRow,documentAmounts} from '../src/process-rules.js';
import {applyFetch} from '../src/process-fetch.js';
import catalog from '../src/admin-catalog.json' with {type:'json'};
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
    'ERP_ADMIN_OPERATIONS_V2','ERP_INITIAL_LOGIN_PASSWORD_POLICY','ERP_WORKSPACE_INTEGRITY','ERP_EXTENSIONS','ERP_PRODUCTION_FLOWS_UPDATE'
  ]){
    await db.exec(readFileSync(new URL(`../supabase/${migration}.sql`,import.meta.url),'utf8'));
    console.log('Applied',migration);
  }
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

  const configs=Object.fromEntries(catalog.map(c=>[c.name,c]));
  const doc=(module,number,qty='10')=>({...freshDocument(module),number,date:'2026-11-23',party:'SQL Customer',status:'APPROVED',assignment:{department:'Accounts',user:'QA owner',due:'2026-12-31'},lines:[{id:number+'-line',code:'P1',description:'Part',quantity:qty,uom:'NOS',rate:'100',discount:'0',cgst:'9',sgst:'9',igst:'0'}]});
  const commit=(changes,expected,action='save')=>db.query('select erp_commit_process($1::jsonb,$2::jsonb,$3)',[JSON.stringify(changes),JSON.stringify(expected),action]);
  const pack=async d=>{
    d.total=documentAmounts(d).gross;
    const snap=await snapshot(),side='dfab-process-'+d.module,key=d.module==='Sales Invoice'?'dfab-erp-sales-invoices-v2':'dfab-erp-'+d.module;
    const changes={[side]:{...(snap.get(side)||{}),[d.number]:d}},expected={[side]:snap.get(side)??null};
    const rows=snap.get(key)||[],index=d.module==='Sales Invoice'?1:0,row=projectRow(d,configs[d.module]?.columns||[]);
    if(d.module!=='Sales Invoice')row.push({version:1,processVersion:1,header:{...d.header,Date:d.date},lines:d.lines,processStatus:d.status});
    changes[key]=[row,...rows.filter(r=>r[index]!==d.number)];expected[key]=snap.get(key)??null;
    if(d.source){const k='dfab-workflow-links-v1';changes[k]=[...(snap.get(k)||[]).filter(l=>l.to!==d.module||l.created!==d.number),{from:d.source.module,reference:d.source.number,to:d.module,created:d.number}];expected[k]=snap.get(k)??null;}
    return {changes,expected};
  };
  const order=doc('Sales Orders','SQL-SO');let state=await pack(order);await commit(state.changes,state.expected);
  const documents=[order];let predecessor=order;
  for(const [module,number,status]of [['Purchase Orders','SQL-PO','APPROVED'],['GRN','SQL-GRN','RELEASED'],['Inward QC','SQL-IQC','PASSED'],['Work Order','SQL-WO','APPROVED'],['Route Cards','SQL-RC','RELEASED'],['Production Output','SQL-OUT','RELEASED'],['Outward QC','SQL-OQC','PASSED'],['Delivery Challan','SQL-DC','RELEASED']]){
   const next=applyFetch(doc(module,number),predecessor,{[predecessor.lines[0].id]:'10'},documents);next.number=number;next.status=status;
   if(module.includes('QC'))next.inspection={inspector:'QA',result:'Passed',accepted:'10',rejected:'0'};
   if(module==='Route Cards')next.operations=[{process:'Weld',machine:'QA Machine',type:'In-house',quantity:'10',status:'Completed',qcRequired:true,qcStatus:'Passed'}];
   state=await pack(next);await commit(state.changes,state.expected);documents.push(next);predecessor=next;
  }
  const dispatch=predecessor;
  const invoice=applyFetch(doc('Sales Invoice','SQL-INV','2'),dispatch,{[dispatch.lines[0].id]:'2'},documents);invoice.number='SQL-INV';invoice.status='APPROVED';
  state=await pack(invoice);await commit(state.changes,state.expected);documents.push(invoice);
  await assert.rejects(commit(state.changes,state.expected),/changed/);
  const excessive=applyFetch(doc('Sales Invoice','SQL-OVER'),dispatch,{[dispatch.lines[0].id]:'8'},documents);excessive.number='SQL-OVER';excessive.status='APPROVED';excessive.lines[0].quantity='9';state=await pack(excessive);await assert.rejects(commit(state.changes,state.expected),/pending source quantity/);
  const forged=structuredClone(order);forged.number='SQL-FORGED';state=await pack(forged);state.changes['dfab-process-Sales Orders']['SQL-FORGED'].total=1;await assert.rejects(commit(state.changes,state.expected),/total/);
  const stale=structuredClone(order);stale.lines[0].quantity='11';state=await pack(stale);await assert.rejects(commit(state.changes,state.expected),/Linked source/);
  const role=(await db.query('select erp_admin_save_role(null,$1,$2,$3,true,$4::jsonb) as id',['PROCESS_MAKER','Process maker','QA',JSON.stringify([{page:'Sales Orders',view:true,create:true,edit:true},{page:'Sales Invoice',view:true,create:true,edit:true}])])).rows[0].id;
  await db.query('select erp_admin_save_user($1,null,$2,true,$3::uuid[])',[staff,'QA Maker',[role]]);await asUser(staff);
  const unauthorised=doc('Sales Orders','SQL-NO-APPROVE');state=await pack(unauthorised);await assert.rejects(commit(state.changes,state.expected),/Approval permission/);
  unauthorised.status='DRAFT';state=await pack(unauthorised);await commit(state.changes,state.expected);
  await assert.rejects(db.query('select * from erp_process_write_authorizations'),/permission denied/);
  await assert.rejects(db.query('select erp_next_process_no($1,$2,$3)',['GRN','GRN','26-27']),/create permission/);
  await asUser(admin);
  const negative=doc('Stock Adjustment','SQL-NEGATIVE','1');negative.status='RELEASED';negative.header['Adjustment direction']='Decrease';state=await pack(negative);await assert.rejects(commit(state.changes,state.expected),/below zero/);
  const premature={...documents.find(d=>d.module==='Work Order'),status:'COMPLETED'};state=await pack(premature);await assert.rejects(commit(state.changes,state.expected,'close'),/payment|full source|delivery/);
  const pay={id:'payment-qa-1',module:'Sales Invoice',invoice:'SQL-INV',date:'2026-11-23',party:'SQL Customer',amount:'200',tds:'36',ld:'0',type:'Cash',reference:''};
  const payKey='dfab-process-payments-Sales Invoice',projection='dfab-erp-Customer Payments';let snap=await snapshot();
  const payRow=[pay.id,pay.party,pay.invoice,pay.date,pay.amount,'Settled',{version:1,header:{'TDS Amount':'36','LD Amount':'0','Invoice Module':'Sales Invoice'}}];
  await commit({[payKey]:[pay],[projection]:[payRow]},{[payKey]:snap.get(payKey)??null,[projection]:snap.get(projection)??null},'payment');
  snap=await snapshot();const excess={...pay,id:'payment-qa-2',amount:'1',tds:'0'};const excessRow=[excess.id,excess.party,excess.invoice,excess.date,'1','Part Paid',{version:1,header:{'TDS Amount':'0','LD Amount':'0','Invoice Module':'Sales Invoice'}}];
  await assert.rejects(commit({[payKey]:[excess,pay],[projection]:[excessRow,payRow]},{[payKey]:snap.get(payKey),[projection]:snap.get(projection)},'payment'),/excessive payment/);
  const paidEdit=structuredClone(invoice);paidEdit.lines[0].rate='101';state=await pack(paidEdit);await assert.rejects(commit(state.changes,state.expected),/allocations/);
  const email=await db.query("select erp_invoice_email_start('SQL-INV','qa@example.test','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') as result");assert.equal(email.rows[0].result.created,true);
  const duplicate=await db.query("select erp_invoice_email_start('SQL-INV','qa@example.test','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') as result");assert.equal(duplicate.rows[0].result.created,false);
  await assert.rejects(db.query("select erp_invoice_email_start('SQL-INV','other@example.test','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')"),/identity changed/);
  console.log('PASS: process SQL commits/projections, source reservations, concurrency, total validation, immutable lineage, maker/approver separation, private authorizations, numbering access and email idempotency.');
}finally{await db.close();}
