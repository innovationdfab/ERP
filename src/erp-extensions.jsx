import React,{useState} from 'react';
import {ArrowRight, Download, Plus, Save, X} from 'lucide-react';
import {todayISO,readStored,csvCell} from './erp-utils.js';
import {writeCloudValueConfirmed} from './backend/cloud-store.js';
import {canAccess} from './admin-permissions.js';
import {freshDocument,snapshotForEdit,saveProcessDocument} from './process-store.js';
import {newLine} from './process-schema.js';
import {extensionAllowed,policyKey,followupKey,reorderRows,validateReorderPolicy,receivableRows,statementRows,validateFollowup,addDays} from './erp-extensions.js';
import './erp-extensions.css';

const columns={
  'Reorder Planning':['Product','Description','UOM','On hand','On order','Open indents','Reorder point','Target','To request','Preferred vendor','Status'],
  'Receivables Ageing':['Invoice','Customer','Currency','Invoice date','Due date','Ageing bucket','Invoice amount','Received','Credits','Balance'],
  'Collection Follow-ups':['Invoice','Customer','Currency','Balance','Next follow-up','Owner','Method','Status','Note'],
  'Customer Statements':['Invoice','Invoice date','Due date','Invoice amount','Received','Credits','Balance','Ageing bucket']
};
const descriptions={
  'Reorder Planning':'Plan replenishment from posted stock, open purchase orders and unconverted indents.',
  'Receivables Ageing':'Review approved invoices and dated, posted receipts and credits as of the selected date.',
  'Collection Follow-ups':'Record internal collection calls, notes, owners and the next follow-up date.',
  'Customer Statements':'Invoice settlement statement with posted receipts and credits. Select a customer and currency.'
};
const blankPolicy={id:'',minimum:'',target:'',vendor:'',leadDays:'0',enabled:true};
const blankFollowup={invoice:'',nextDate:todayISO(),owner:'',channel:'Phone',status:'Open',note:''};
const format=value=>typeof value==='number'?value.toLocaleString('en-IN',{maximumFractionDigits:2}):value||'—';
function exportRows(title,headers,rows){
  const csv='\ufeff'+[headers,...rows].map(row=>row.map(value=>csvCell(value??'')).join(',')).join('\r\n');
  const href=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));
  const anchor=document.createElement('a');anchor.href=href;anchor.download=`${title}.csv`;anchor.click();
  setTimeout(()=>URL.revokeObjectURL(href),1000);
}

export function ErpExtensions({title,access,readDocuments,readRows,readDetails,goToPage,configs}){
  const [policies,setPolicies]=useState(()=>readStored(policyKey,[]));
  const [followups,setFollowups]=useState(()=>readStored(followupKey,[]));
  const [editor,setEditor]=useState(null);
  const [form,setForm]=useState({});
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const [message,setMessage]=useState('');
  const [query,setQuery]=useState('');
  const [asOn,setAsOn]=useState(todayISO());
  const [customer,setCustomer]=useState('');
  const [currency,setCurrency]=useState('');
  const [status,setStatus]=useState('All');
  const [page,setPage]=useState(1);
  const can=action=>canAccess(access,title,action);
  const ready=extensionAllowed(title,source=>canAccess(access,source,'view'));
  const products=ready?readRows('dfab-erp-products-v3'):[];
  const vendors=ready?readRows('dfab-erp-vendors-v2'):[];
  const allInvoices=ready&&title!=='Reorder Planning'?receivableRows(readDocuments,readDetails):[];
  const policyRows=ready&&title==='Reorder Planning'?reorderRows(policies,readRows,readDocuments):[];
  const invoices=ready&&title==='Receivables Ageing'?receivableRows(readDocuments,readDetails,asOn):allInvoices;
  const customers=[...new Set(allInvoices.map(row=>row.customer))].sort();
  const currencies=[...new Set(allInvoices.filter(row=>row.customer===customer).map(row=>row.currency))].sort();
  const statement=ready&&title==='Customer Statements'&&customer?statementRows(customer,currency,readDocuments,readDetails,asOn):[];
  const invoiceByNumber=new Map(allInvoices.map(row=>[row.number,row]));
  let records=[];
  if(title==='Reorder Planning')records=policyRows.map(row=>({id:row.id,data:row,values:[row.id,row.product?.[1],row.product?.[4],row.stock,row.onOrder,row.requested,row.minimum,row.target,row.quantity,vendors.find(v=>v[0]===row.vendor)?.[1]||row.vendor,row.status]}));
  if(title==='Receivables Ageing')records=invoices.filter(row=>row.balance>0).map(row=>({id:row.number,data:row,values:[row.number,row.customer,row.currency||'Unspecified',row.date,row.due,row.bucket,row.amount,row.received,row.credited,row.balance]}));
  if(title==='Collection Follow-ups')records=followups.flatMap(row=>{
    const invoice=invoiceByNumber.get(row.invoice);
    if(!invoice)return [];
    const visibleStatus=invoice.balance<=0?'Invoice settled':row.status;
    return status!=='All'&&visibleStatus!==status?[]:[{id:row.id,data:row,values:[row.invoice,invoice.customer,invoice.currency||'Unspecified',invoice.balance,row.nextDate,row.owner,row.channel,visibleStatus,row.note]}];
  });
  if(title==='Customer Statements')records=statement.map(row=>({id:row.number,data:row,values:[row.number,row.date,row.due,row.amount,row.received,row.credited,row.balance,row.bucket]}));
  const filtered=records.filter(row=>row.values.join(' ').toLowerCase().includes(query.toLowerCase().trim()));
  const pageCount=Math.max(1,Math.ceil(filtered.length/20));
  const activePage=Math.min(page,pageCount);
  const start=editing=>{
    setError('');setMessage('');
    setEditor(editing?.id||'new');
    setForm(title==='Reorder Planning'?editing?{...editing}: {...blankPolicy}:editing?{...editing}: {...blankFollowup});
  };
  const change=(key,value)=>setForm(current=>({...current,[key]:value}));
  const save=async event=>{
    event.preventDefault();
    if(busy||!ready||!can(editor==='new'?'create':'edit'))return;
    const issue=title==='Reorder Planning'?validateReorderPolicy(form,products,vendors):validateFollowup(form,allInvoices,editor!=='new');
    if(issue){setError(issue);return;}
    const policiesMode=title==='Reorder Planning';
    const before=policiesMode?policies:followups;
    if(policiesMode&&editor==='new'&&before.some(row=>row.id===form.id)){setError('A reorder policy already exists for this product. Edit that policy.');return;}
    const value=policiesMode?{id:form.id,minimum:Number(form.minimum),target:Number(form.target),vendor:form.vendor,
      leadDays:Number(form.leadDays),enabled:!!form.enabled,updatedAt:new Date().toISOString()}
      :{id:editor==='new'?crypto.randomUUID():editor,invoice:form.invoice,nextDate:form.nextDate,
        owner:form.owner.trim(),channel:form.channel,status:form.status,note:form.note.trim(),updatedAt:new Date().toISOString()};
    const next=editor==='new'?[value,...before]:before.map(row=>row.id===editor?value:row);
    setBusy(true);setError('');setMessage('');
    try{
      await writeCloudValueConfirmed(policiesMode?policyKey:followupKey,next,before);
      if(policiesMode)setPolicies(next);else setFollowups(next);
      setEditor(null);setMessage('Saved successfully.');
    }catch(problem){setError(problem.message);}
    finally{setBusy(false);}
  };
  const createIndent=async policy=>{
    if(busy||!ready||!canAccess(access,'Purchase Indents','create'))return;
    const current=reorderRows(policies,readRows,readDocuments).find(row=>row.id===policy.id);
    if(!current||current.quantity<=0){setError('The request is already covered. Review the latest stock and open indents.');return;}
    const issue=validateReorderPolicy(current,products,vendors);
    if(issue){setError(issue);return;}
    const vendor=vendors.find(row=>row[0]===current.vendor);
    const document={...freshDocument('Purchase Indents'),party:vendor[1],
      header:{Department:'Stores','Required Date':addDays(todayISO(),current.leadDays),
        'Reorder Policy ID':current.id,'Indent Remarks':'Created from Reorder Planning'},
      lines:[{...newLine(),code:current.id,description:current.product[1],uom:current.product[4],
        quantity:String(current.quantity),cgst:'0',sgst:'0'}]};
    setBusy(true);setError('');setMessage('');
    try{
      const saved=await saveProcessDocument(document,configs,snapshotForEdit());
      const number=saved.number;
      setMessage(`Draft purchase indent ${number} created for ${current.quantity} ${current.product[4]}.`);
    }catch(problem){setError(problem.message);}
    finally{setBusy(false);}
  };
  const unknown=invoices.some(row=>row.unknownAllocations>0);
  return <main className="content page-shell extension-page">
    <div className="page-title-row"><div><h1>{title}</h1><p className="page-subtitle">{descriptions[title]}</p></div>
      <div className="action-pills">
        <button type="button" className="action-pill gray" disabled={!ready||!can('export')} onClick={()=>exportRows(title,columns[title],filtered.map(row=>row.values))}><Download size={15}/> Export CSV</button>
        {['Reorder Planning','Collection Follow-ups'].includes(title)&&<button type="button" className="primary-pill" disabled={!ready||busy||!can('create')} onClick={()=>start()}><Plus size={16}/>{title==='Reorder Planning'?'Add reorder policy':'Add follow-up'}</button>}
      </div>
    </div><div className="divider"/>
    {!ready?<p role="status" className="data-notice">View access to this section and its source modules is required. Ask an administrator to assign the required rights.</p>:<>
      {error&&<p role="alert" className="transaction-editor-error">{error}</p>}
      {message&&<p role="status">{message}</p>}
      {editor&&<form className="card extension-editor" onSubmit={save} aria-label={title==='Reorder Planning'?'Reorder policy':'Collection follow-up'}>
        <h2>{editor==='new'?'Create':'Edit'} {title==='Reorder Planning'?'reorder policy':'follow-up'}</h2>
        <div className="erp-form-grid">
          {title==='Reorder Planning'?<>
            <label><span>Product</span><select aria-label="Product" required value={form.id} disabled={editor!=='new'||busy} onChange={event=>change('id',event.target.value)}><option value="">Select product</option>{products.filter(row=>row[6]==='ACTIVE').map(row=><option key={row[0]} value={row[0]}>{row[0]} · {row[1]}</option>)}</select></label>
            <label><span>Preferred vendor</span><select aria-label="Preferred vendor" required value={form.vendor} disabled={busy} onChange={event=>change('vendor',event.target.value)}><option value="">Select vendor</option>{vendors.filter(row=>row[8]==='ACTIVE').map(row=><option key={row[0]} value={row[0]}>{row[0]} · {row[1]}</option>)}</select></label>
            {[['Reorder point','minimum'],['Target stock','target'],['Lead time in days','leadDays']].map(([label,key])=><label key={key}><span>{label}</span><input aria-label={label} required type="number" min="0" step={key==='leadDays'?'1':'any'} max={key==='leadDays'?'365':undefined} value={form[key]} disabled={busy} onChange={event=>change(key,event.target.value)}/></label>)}
            <label className="extension-checkbox"><input type="checkbox" checked={form.enabled} disabled={busy} onChange={event=>change('enabled',event.target.checked)}/><span>Enabled</span></label>
          </>:<>
            <label><span>Invoice</span><select aria-label="Invoice" required value={form.invoice} disabled={busy||editor!=='new'} onChange={event=>change('invoice',event.target.value)}><option value="">Select outstanding invoice</option>{allInvoices.filter(row=>row.balance>0||row.number===form.invoice).map(row=><option key={row.number} value={row.number}>{row.number} · {row.customer} · {row.currency||'Unspecified'} {row.balance}</option>)}</select></label>
            <label><span>Next follow-up</span><input aria-label="Next follow-up" type="date" required value={form.nextDate} disabled={busy} onChange={event=>change('nextDate',event.target.value)}/></label>
            <label><span>Owner</span><input aria-label="Owner" required maxLength={120} value={form.owner} disabled={busy} onChange={event=>change('owner',event.target.value)}/></label>
            <label><span>Contact method</span><select aria-label="Contact method" value={form.channel} disabled={busy} onChange={event=>change('channel',event.target.value)}>{['Phone','Email','Meeting','Other'].map(value=><option key={value}>{value}</option>)}</select></label>
            <label><span>Status</span><select aria-label="Status" value={form.status} disabled={busy} onChange={event=>change('status',event.target.value)}>{['Open','Done'].map(value=><option key={value}>{value}</option>)}</select></label>
            <label className="extension-note"><span>Note</span><textarea aria-label="Note" required maxLength={2000} value={form.note} disabled={busy} onChange={event=>change('note',event.target.value)}/></label>
          </>}
        </div>
        <div className="action-pills"><button type="submit" className="action-pill blue" disabled={busy}><Save size={15}/>{busy?'Saving…':'Save'}</button><button type="button" className="action-pill gray" disabled={busy} onClick={()=>{setEditor(null);setError('');}}><X size={15}/>Cancel</button></div>
      </form>}
      <section className="card extension-register">
        <div className="extension-filters">
          <label><span>Search</span><input aria-label="Search" type="search" value={query} onChange={event=>{setQuery(event.target.value);setPage(1);}}/></label>
          {['Receivables Ageing','Customer Statements'].includes(title)&&<label><span>As of date</span><input aria-label="As of date" type="date" required max={todayISO()} value={asOn} onChange={event=>{if(event.target.value&&event.target.value<=todayISO()){setAsOn(event.target.value);setPage(1);}}}/></label>}
          {title==='Customer Statements'&&<>
            <label><span>Customer</span><select aria-label="Customer" value={customer} onChange={event=>{setCustomer(event.target.value);setCurrency(allInvoices.find(row=>row.customer===event.target.value)?.currency||'');setPage(1);}}><option value="">Select customer</option>{customers.map(value=><option key={value}>{value}</option>)}</select></label>
            <label><span>Currency</span><select aria-label="Currency" value={currency} onChange={event=>{setCurrency(event.target.value);setPage(1);}}>{currencies.length?currencies.map(value=><option key={value} value={value}>{value||'Unspecified'}</option>):<option value="">Unspecified</option>}</select></label>
          </>}
          {title==='Collection Follow-ups'&&<label><span>Show status</span><select aria-label="Show status" value={status} onChange={event=>{setStatus(event.target.value);setPage(1);}}>{['All','Open','Done','Invoice settled'].map(value=><option key={value}>{value}</option>)}</select></label>}
          <span role="status">{filtered.length} records</span>
        </div>
        {unknown&&title!=='Reorder Planning'&&<p className="data-notice">Some posted allocations have no saved date. Their amounts require date verification before inclusion.</p>}
        {title==='Customer Statements'&&customer&&<p className="data-notice">Balance as of {asOn} · {currency||'Unspecified currency'} {format(statement.reduce((sum,row)=>sum+row.balance,0))}</p>}
        <div className="table-wrap extension-table" tabIndex={0} aria-label={`${title} results`}><table>
          <thead><tr>{columns[title].map(column=><th scope="col" key={column}>{column}</th>)}<th scope="col" className="extension-actions-cell">Actions</th></tr></thead>
          <tbody>{filtered.slice((activePage-1)*20,activePage*20).map(row=><tr key={row.id}>{row.values.map((value,index)=><td key={columns[title][index]}>{format(value)}</td>)}<td className="extension-actions-cell"><div className="extension-row-actions">
            {title==='Reorder Planning'?<>
              <button type="button" className="action-pill gray" disabled={busy||!can('edit')} onClick={()=>start(row.data)}>Edit policy</button>
              <button type="button" className="action-pill blue" disabled={busy||row.data.quantity<=0||!canAccess(access,'Purchase Indents','create')} onClick={()=>createIndent(row.data)}>Create indent</button>
            </>:<>
              {title==='Collection Follow-ups'&&<button type="button" className="action-pill gray" disabled={busy||!can('edit')} onClick={()=>start(row.data)}>Edit follow-up</button>}
              <button type="button" className="action-pill gray" onClick={()=>goToPage('Sales Invoice',null,row.data.invoice||row.id)}>Open invoice <ArrowRight size={14}/></button>
            </>}
          </div></td></tr>)}
          {!filtered.length&&<tr><td className="empty-cell" colSpan={columns[title].length+1}>{title==='Customer Statements'&&!customer?'Select a customer to view the statement.':'No matching records.'}</td></tr>}
          </tbody></table></div>
        <div className="data-table-foot"><span>Page {activePage} of {pageCount}</span><div className="pagination"><button disabled={activePage===1} onClick={()=>setPage(activePage-1)}>Previous</button><button disabled={activePage===pageCount} onClick={()=>setPage(activePage+1)}>Next</button></div></div>
      </section>
    </>}
  </main>;
}
