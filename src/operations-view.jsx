import {matchesSearch} from './filter-rules.js';
import React,{useMemo,useState} from 'react';
import {ArrowUpRight, ChevronLeft, ChevronRight, Search} from 'lucide-react';
import {operationPages,operationRows,connectedOperations} from './operations-views.js';
import {hasDocumentValue} from './document-data.js';

const summaries={
  'RM Inward and Outward':'Posted movements for products classified as raw materials.',
  'Customer Payment Overdue':'Approved invoices with an outstanding balance and a saved due date before today.'
};
const linkedPages=new Set(['PO Number Details','SO Number Details','Route Card Monitoring']);

export function OperationsView({title,readDocuments,readRows,readObject,canRead,openRecord}){
  const [query,setQuery]=useState('');
  const [page,setPage]=useState(1);
  const [selected,setSelected]=useState(null);
  const config=operationPages[title];
  const results=useMemo(()=>operationRows(title,{readDocuments,readRows,readObject,canRead}),[title,readDocuments,readRows,readObject,canRead]);
  const filtered=results.filter(row=>matchesSearch(row.values,query));
  const pageCount=Math.max(1,Math.ceil(filtered.length/25));
  const visiblePage=Math.min(page,pageCount);
  const related=selected?connectedOperations(selected.module,selected.reference,readRows('dfab-workflow-links-v1'),readDocuments,canRead):[];
  return <main className="content page-shell live-report-page operations-page">
    <div className="page-title-row"><div><h1>{title}</h1>{summaries[title]&&<p className="page-subtitle">{summaries[title]}</p>}</div></div>
    <div className="divider"/>
    <section className="card live-report-sheet operations-register" aria-label={title}>
      <div className="table-controls">
        <span>{filtered.length.toLocaleString('en-IN')} record{filtered.length===1?'':'s'}</span>
        <label className="operations-search"><Search size={16}/><span>Search</span>
          <input type="search" value={query} onChange={event=>{setQuery(event.target.value);setPage(1);setSelected(null);}}/>
        </label>
      </div>
      <div className="table-wrap operations-table" tabIndex={0} aria-label="Results">
        <table><thead><tr>{config.columns.map(column=><th scope="col" key={column}>{column}</th>)}
          <th scope="col">Actions</th></tr></thead>
        <tbody>{filtered.slice((visiblePage-1)*25,visiblePage*25).map(({values,module,reference})=><tr key={JSON.stringify([module,reference])}>
          {values.map((value,index)=><td key={config.columns[index]}>{index===0&&canRead(module)
            ?<button type="button" className="link-button" onClick={()=>openRecord(module,reference)}>{value}</button>
            :hasDocumentValue(value)?value:'—'}</td>)}
          <td>{linkedPages.has(title)?<button type="button" className="action-pill gray" aria-label={`Related documents for ${reference}`}
            aria-expanded={selected?.reference===reference} onClick={()=>setSelected(selected?.reference===reference?null:{module,reference})}>
            Related documents</button>:canRead(module)?<button type="button" className="action-pill gray"
            onClick={()=>openRecord(module,reference)}>Open register <ArrowUpRight size={14}/></button>:null}</td>
        </tr>)}
        {!filtered.length&&<tr><td colSpan={config.columns.length+1} className="empty-cell">No matching records.</td></tr>}</tbody></table>
      </div>
      {pageCount>1&&<div className="operations-pagination">
        <button type="button" className="action-pill gray" disabled={visiblePage===1} onClick={()=>setPage(visiblePage-1)} aria-label="Previous page"><ChevronLeft size={16}/></button>
        <span>Page {visiblePage} of {pageCount}</span>
        <button type="button" className="action-pill gray" disabled={visiblePage>=pageCount} onClick={()=>setPage(visiblePage+1)} aria-label="Next page"><ChevronRight size={16}/></button>
      </div>}
    </section>
    {selected&&<section className="card operations-related" aria-label="Related documents">
      <h2>Related documents for {selected.reference}</h2>
      {!related.length?<p className="data-notice">No linked documents available for your role.</p>:<ul>{related.map(item=>
        <li key={JSON.stringify([item.module,item.reference])}>
          <span>{item.module}</span><button type="button" className="link-button" onClick={()=>openRecord(item.module,item.reference)}>{item.reference}</button>
          {hasDocumentValue(item.status)&&<span className="status-pill pending">{item.status}</span>}
        </li>)}</ul>}
    </section>}
  </main>;
}
