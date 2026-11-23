import test from 'node:test';import assert from 'node:assert/strict';
import {schemas,newLine} from '../src/process-schema.js';
import {validateDocument,validateReleaseChain,documentAmounts,projectRow} from '../src/process-rules.js';
import {applyFetch,fetchSourceTypes,fetchSourceIssue} from '../src/process-fetch.js';
import {writeCloudValue,setCloudAccessToken} from '../src/backend/cloud-store.js';
import {processDocuments,freshDocument} from '../src/process-store.js';
import {postedStockMovements} from '../src/imantra-stock.js';
import {invoiceMailHtml} from '../src/invoice-mail.js';
const valid=module=>({...freshDocument(module),number:'QA-1',party:'QA Customer',date:'2026-11-23',status:'APPROVED',header:{'Customer PO Dt.':'2026-11-23','C Number':'C1','A Number':'A1'},lines:[{...newLine(),code:'P1',description:'Part',quantity:'2',rate:'100',uom:'NOS'}],assignment:{department:'Accounts',user:'QA user',due:'2026-12-31'}});
test('existing warehouse, machine and return references remain in the expanded headers',()=>{
 assert.ok(schemas['Work Order'].fields.includes('Machine'));
 assert.ok(schemas['Material Issue'].fields.includes('Store'));
 assert.ok(schemas['Sales Return'].fields.includes('Invoice'));
 for(const name of ['In-process QC','Job Work QC','Material Request','Job Work Return DC'])assert.ok(fetchSourceTypes(name).length,name);
});
test('draft sources are hidden and passed inward QC can feed manufacturing work orders',()=>{
 const qc={...valid('Inward QC'),status:'PASSED',inspection:{result:'Passed'}};
 assert.equal(fetchSourceIssue(qc,'Work Order'),'');assert.match(fetchSourceIssue({...qc,status:'APPROVAL PENDING'},'Work Order'),/release/);
});
test('release requires physical QC and dispatch lineage while drafts remain editable',()=>{
 assert.match(validateReleaseChain(valid('Delivery Challan'),[]),/outward QC/);
 assert.match(validateReleaseChain(valid('Sales Invoice'),[]),/challan/);
 assert.match(validateReleaseChain(valid('Work Order'),[]),/inward QC/);
 assert.equal(validateReleaseChain({...valid('Sales Invoice'),status:'DRAFT'},[]),'');
});
test('inspection measurement limits are checked before a passed release',()=>{
 const d={...valid('In-process QC'),header:{'WO No':'WO1',Operation:'Weld',Inspector:'QA',Disposition:'Passed'},inspection:{inspector:'QA',result:'Passed',accepted:'2',rejected:'0',characteristics:[{name:'Diameter',unit:'mm',min:'9',max:'11',actual:'12'}]}};
 assert.match(validateDocument(d),/outside/);d.inspection.characteristics[0].actual='10';assert.equal(validateDocument(d),'');
});
test('multiple lines and GST amounts retain their legacy register positions',()=>{
 const d={...valid('Sales Orders'),lines:[...valid('Sales Orders').lines,{...newLine(),code:'P2',quantity:'3',rate:'50'}]};
 const row=projectRow(d,['SO No','Customer','Customer PO','Product','Qty','Delivery','Status']);assert.equal(row[4],'5');assert.equal(row[6],'Approved');assert.equal(documentAmounts(d).gross,413);
});
test('stock views read every saved line and the verified date without duplicating receipt quantities',()=>{
 const trailer={version:1,processVersion:1,header:{Date:'2026-11-23'},lines:[{code:'P1',quantity:'2',rate:'100'},{code:'P2',quantity:'3',rate:'50'}]};
 const rows=[['GRN1','PO1','Vendor','P1','5','Accepted',trailer]];
 const moves=postedStockMovements(key=>key==='dfab-erp-GRN'?rows:[]);assert.equal(moves.length,2);assert.deepEqual(moves.map(m=>m.qty),[2,3]);assert.ok(moves.every(m=>m.date==='2026-11-23'));
});
test('legacy headers, attachments, original totals and missing dates survive adaptation',()=>{
 setCloudAccessToken('unit-legacy');
 const config={columns:['PO No','Vendor','PO Date','Amount','Delivery Date','Status']};
 writeCloudValue('dfab-erp-Purchase Orders',[['OLD-PO','Vendor','-','1,250','-','Approved',{version:1,header:{'Project Name':'Original'},files:{quote:{name:'quote.pdf',dataUrl:'data:application/pdf;base64,AA=='}}}]]);
 const [d]=processDocuments('Purchase Orders',{'Purchase Orders':config});assert.equal(d.total,1250);assert.equal(d.date,'');assert.equal(d.header['Project Name'],'Original');assert.equal(d.attachments.quote.name,'quote.pdf');assert.equal(d.legacy,true);setCloudAccessToken('');
});
test('published administrator workflow gates remain enforced',()=>{
 const d={...valid('Sales Orders'),workflowNext:'Work Order',workflowGates:['Released'],status:'APPROVED'};
 const target=freshDocument('Work Order');assert.throws(()=>applyFetch(target,d,{[d.lines[0].id]:'1'},[d]),/gate/);
});
test('invoice copies escape document, customer and line content',()=>{
 const html=invoiceMailHtml({...valid('Sales Invoice'),party:'<script>bad()</script>',lines:[{...newLine(),description:'<img onerror=bad()>',rate:1}],total:1});
 assert.ok(!html.includes('<script>'));assert.match(html,/&lt;script&gt;/);assert.ok(!html.includes('<img onerror'));
});
