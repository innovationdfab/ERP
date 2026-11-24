import test from 'node:test';import assert from 'node:assert/strict';
import {isoDate} from '../src/erp-utils.js';
import {matchesSearch,withinDateRange,dateRangeIssue,reportParameterMatches} from '../src/filter-rules.js';
import {freshDocument,forwardProcessDocument,takePendingOpen} from '../src/process-store.js';
import {applyFetch} from '../src/process-fetch.js';
import {documentAmounts,validateDocument} from '../src/process-rules.js';
import {stockReportRows} from '../src/imantra-stock.js';
import {receivableRows} from '../src/erp-extensions.js';
import {confirmedOperation} from '../src/operation-feedback.js';
const line=(id,quantity,rate,discount='0')=>({id,code:id,description:'QA '+id,quantity,uom:'NOS',rate,discount,cgst:'9',sgst:'9',igst:'0'});
const quotation=()=>({...freshDocument('Sales Quotations'),number:'SQ/QA',party:'QA Customer',status:'APPROVED',header:{'Project Name':'QA-PROJECT','PO Number':'CPO/QA','Currency Type':'USD'},lines:[line('A','2','100','10'),line('B','1','50')],charges:[{id:'freight',description:'Freight',amount:'10',cgst:'9',sgst:'9',igst:'0'}],adjustment:'-0.2'});
test('date filters normalize legacy input and include both endpoints without admitting undated records',()=>{
 for(const value of ['24-Nov-2026','24 November 2026','24/11/2026','24.11.2026','2026-11-24T10:50:00Z'])assert.equal(isoDate(value),'2026-11-24');
 assert.equal(isoDate('31/02/2026'),'');assert.equal(withinDateRange('24-Nov-2026','2026-11-24','2026-11-24'),true);assert.equal(withinDateRange('', '', '2026-11-24'),false);assert.equal(withinDateRange('', '', ''),true);assert.match(dateRangeIssue('2026-12-01','2026-11-01'),/From date/);
});
test('search supports extra spaces, multiple words and nested line/reference fields',()=>{assert.ok(matchesSearch({party:'  QA Customer ',lines:[{code:'BRACKET-01'}]},' bracket-01   qa '));assert.equal(matchesSearch('QA Customer','supplier qa'),false);assert.ok(matchesSearch('All records','  '));});
test('as-of report parameters are inclusive and stock reports do not filter their computed closing rows twice',()=>{
 assert.ok(reportParameterMatches('Pending Receivables',['Invoice Date'],['24-Nov-2026'],{kind:'date',key:'asOnDate'},'2026-11-30'));
 assert.equal(reportParameterMatches('Pending Receivables',['Invoice Date'],['24-Nov-2026'],{kind:'date',key:'fromDate'},'2026-11-25'),false);
 assert.ok(reportParameterMatches('Inventory Ageing',['Last Date'],['2026-01-01'],{kind:'date',key:'asOnDate'},'2026-11-30'));
});
test('full quotation conversion keeps agreed 283 amount and source references',()=>{const q=quotation(),so=applyFetch(freshDocument('Sales Orders'),q,{A:2,B:1},[q]);assert.equal(so.total,283);assert.equal(so.charges[0].amount,'10');assert.equal(so.adjustment,'-0.2');assert.equal(so.header['Project Name/Code'],'QA-PROJECT');assert.equal(so.context['Currency Type'],'USD');assert.equal(q.adjustment,'-0.2');});
test('partial conversions allocate charges and signed rounding once across all children',()=>{const q=quotation(),first=applyFetch(freshDocument('Sales Orders'),q,{A:1},[q]);first.number='SO/1';const second=applyFetch(freshDocument('Sales Orders'),q,{A:1,B:1},[q,first]);assert.equal(Number(first.charges[0].amount)+Number(second.charges[0].amount),10);assert.equal(Math.round((first.total+second.total)*100)/100,283);assert.equal(Math.round((Number(first.adjustment)+Number(second.adjustment))*100)/100,-0.2);});
test('project, customer PO and currency survive QC/store hops and different procurement pricing',()=>{
 const so={...quotation(),module:'Sales Orders',number:'SO/QA',header:{'Project Name/Code':'QA-PROJECT','PO Number':'CPO/QA','Currency Type':'USD'},lines:[{...line('SO-A','2','100','10'),rootLineId:'root-A'}]};
 const qc={...freshDocument('Outward QC'),number:'OQC/QA',party:'QA Customer',status:'PASSED',inspection:{result:'Passed'},references:{'Sales Orders':'SO/QA'},lines:[{...line('QC-A','2','1','10'),rootLineId:'root-A'}]};
 const dc=applyFetch(freshDocument('Delivery Challan'),qc,{'QC-A':2},[so,qc]);assert.equal(dc.header['Project Name'],'QA-PROJECT');assert.equal(dc.header['PO Number'],'CPO/QA');assert.equal(dc.charges[0].amount,'10');dc.number='DC/QA';dc.status='DELIVERED';
 const invoice=applyFetch(freshDocument('Sales Invoice'),dc,{[dc.lines[0].id]:2},[so,qc,dc]);assert.equal(invoice.header['Currency Type'],'USD');assert.equal(invoice.header['Buyer PO No.'],'CPO/QA');assert.equal(invoice.header['Project Name'],'QA-PROJECT');
});
test('vendor handoff opens unsaved target without any database call or number allocation',async()=>{
 const so={...quotation(),module:'Sales Orders',number:'SO/QA'};const target=await forwardProcessDocument(so,'Purchase Orders',{});assert.equal(target.number,'');assert.equal(target.party,'');assert.equal(target.source.number,'SO/QA');assert.equal(takePendingOpen('Purchase Orders').document.lines.length,2);
});
test('new invoice exposes an explicit due date and validates credit-days input',()=>{const invoice=freshDocument('Sales Invoice');assert.equal(invoice.header['Due Date'],invoice.date);invoice.header['Credit Days']='bad';assert.match(validateDocument({...invoice,party:'QA',lines:[line('A','1','1')]},{draft:true}),/Credit Days/);assert.equal(documentAmounts({...quotation()}).gross,283);});
test('stock ledger retains saved description and UOM without a product master row',()=>{const trailer={version:1,processVersion:1,header:{Date:'2026-11-24'},lines:[line('QA-SKU','2','100')]};const readRows=k=>k==='dfab-erp-Opening Stock'?[['OS/1','QA-SKU','Stores','2','100','Posted',trailer]]:[];assert.deepEqual(stockReportRows('Stock Ledger',['Description','UOM','Inward'],readRows,{},{}),[['QA QA-SKU','NOS',2]]);});
test('cash received is separate from TDS/LD while settlement balance stays zero',()=>{
 const records={'Sales Invoice':[{number:'SI/1',fields:{'Invoice No':'SI/1',Date:'2026-11-24',Customer:'QA',Status:'APPROVED',Amount:271.4}}],'Customer Payments':[{fields:{Invoice:'SI/1',Date:'2026-11-24',Status:'Settled',Amount:260.4,'TDS Amount':10,'LD Amount':1}}],'Credit Note':[]};
 const row=receivableRows(name=>records[name]||[],()=>({'SI/1':{form:{date:'2026-11-24',dueDate:'2026-12-24',currency:'INR'}}}),'2026-11-24')[0];assert.equal(row.received,260.4);assert.equal(row.tds,10);assert.equal(row.ld,1);assert.equal(row.settled,271.4);assert.equal(row.balance,0);assert.equal(row.due,'2026-12-24');
});
test('confirmed feedback distinguishes saved, approved, deleted and rejected operations',()=>{assert.equal(confirmedOperation('save',{}, {x:{status:'APPROVAL PENDING'}}),'Submitted for approval');assert.equal(confirmedOperation('approve',{},{}),'Approved');assert.equal(confirmedOperation('delete',[],[]),'Deleted');assert.equal(confirmedOperation('reject',{},{}),'Rejected');assert.equal(confirmedOperation('save',{},{}),'Saved');assert.equal(confirmedOperation('save',[['A','Draft']],[['A','Approved']]),'Approved');assert.equal(confirmedOperation('save',[['A','Approved']],[['A','Approved','Updated remarks']]),'Saved');});
