import React, { useEffect, useRef, useState } from 'react';
import { ArrowLeft, RefreshCw } from 'lucide-react';
import { PremiumUploadField } from './premium-forms.jsx';
import { isoDate } from './erp-utils.js';
import { referenceFetch } from './reference-forms.js';
import { allowedFetchRecord } from './document-fetch.js';

const documentExtensions='.png,.jpg,.jpeg,.webp,.gif,.pdf,.txt,.csv,.xlsx,.xls,.docx,.doc';
const suggestionLabel={
  'Next Task Assigned to':'Assigned user',
  'Managed By':'User',
  'Purchased By':'User',
  'Kind Attention':'Kind Attention'
};

function readReferenceAttachment(file) {
  if(!file) return Promise.resolve(null);
  return new Promise((resolve,reject)=>{
    const reader=new FileReader();
    reader.onload=()=>resolve({name:file.name,dataUrl:reader.result});
    reader.onerror=()=>reject(new Error('Could not read this attachment.'));
    reader.readAsDataURL(file);
  });
}

export function ReferenceField({field,value,onChange,Suggest}) {
  const {label,key,type,options,required}=field;
  return <label>
    <span className={required?'transaction-required':undefined}>{label}</span>
    {options ? <select value={value || ''} onChange={event=>onChange(key,event.target.value)} required={required}>
      <option value="">Select {label}</option>
      {value && !options.includes(value) && <option>{value}</option>}
      {options.map(option=><option key={option}>{option}</option>)}
    </select> : type==='textarea' ? <textarea value={value ?? ''} onChange={event=>onChange(key,event.target.value)}/>
      : React.createElement(Suggest,{
        label:suggestionLabel[label]||label,type,required,
        value:type==='date'?isoDate(value):value ?? '',
        min:type==='number'?0:undefined,step:type==='number'?'any':undefined,
        onChange:event=>onChange(key,event.target.value)
      })}
  </label>;
}

export function ReferenceAttachments({labels,files,onChange,disabled,onReading}) {
  return <div className="reference-attachments">
    {labels.map(label=><section className="transaction-attachment-card" key={label}>
      <h3>{label}</h3>
      <PremiumUploadField compact label={label} value={files[label]} disabled={disabled} accept={documentExtensions} onSelect={async file=>{
        onReading(true);
        try {
          const data=await readReferenceAttachment(file);
          onChange(label,data);
        } finally { onReading(false); }
      }}/>
      {files[label]?.dataUrl && <a href={files[label].dataUrl} download={files[label].name}>Download {files[label].name}</a>}
    </section>)}
  </div>;
}

export function ReferenceFetch({title,getRecords,onFetch,disabled=false}) {
  const sources=referenceFetch[title];
  const [expanded,setExpanded]=useState(false);
  const [sourceIndex,setSourceIndex]=useState(0);
  const [number,setNumber]=useState('');
  const [query,setQuery]=useState('');
  const [applied,setApplied]=useState('');
  const [fetchError,setFetchError]=useState('');
  const panelId=React.useId();
  const trigger=useRef(null);
  if (!sources?.length) return null;
  const source=sources[sourceIndex];
  const records=expanded?getRecords(source.module).filter(record=>allowedFetchRecord(source,record)):[];
  const terms=query.trim().toLowerCase().split(/\s+/);
  const matches=records.filter(record=>{
    const text=`${record.number} ${record.party||''}`.toLowerCase();
    return terms.every(term=>text.includes(term));
  });
  const selected=matches.find(record=>record.number===number);
  const choose=()=>{
    if (!selected) return;
    const error=onFetch(source,selected);
    if(error){setFetchError(error);return;}
    setFetchError('');
    setApplied(`${source.module} · ${number}`);
    setExpanded(false);
    trigger.current?.focus();
  };
  return <>
    <div className="transaction-fetch-trigger">
    <button ref={trigger} type="button" className="action-pill blue" disabled={disabled} aria-expanded={expanded}
      aria-controls={panelId} onClick={()=>{setFetchError('');setExpanded(!expanded);}}><RefreshCw size={15}/> Fetch</button>
    {applied && <span role="status">Fetched from {applied}</span>}
    </div>
    <div className="transaction-fetch-panel" id={panelId} hidden={!expanded}>
      <div className="modal-grid reference-fetch-grid">
        <label><span>Source type</span><select value={sourceIndex} onChange={event=>{
          setSourceIndex(Number(event.target.value));
          setNumber('');
          setFetchError('');
        }}>{sources.map(({module},index)=><option key={module} value={index}>{module}</option>)}</select></label>
        <label><span>Find by number or party</span><input type="search" value={query} onChange={event=>{
          setQuery(event.target.value);
          setNumber('');
          setFetchError('');
        }}/></label>
        <label><span>Source document</span><select value={number} onChange={event=>{setNumber(event.target.value);setFetchError('');}}>
          <option value="">Select a document</option>
          {matches.map(record=><option key={record.number} value={record.number}>{record.number}{record.party?` · ${record.party}`:''}</option>)}
        </select></label>
        <button type="button" className="action-pill blue" disabled={!selected || disabled} onClick={choose}>Fetch document</button>
      </div>
      {fetchError&&<p role="alert">{fetchError}</p>}
      {!matches.length && <p role="status">{records.length?'No documents match the search.':'No saved source documents available.'}</p>}
    </div>
  </>;
}

export function ReferenceSections({sections,active,onChange}) {
  if (sections.length<2) return null;
  return <nav className="reference-sections" aria-label="Form sections">
    {sections.map(section=><button type="button" key={section} aria-current={section===active?'true':undefined}
      className="transaction-section-tab" onClick={()=>onChange(section)}>{section}</button>)}
  </nav>;
}

export function TransactionEditor({title,reference,busy,onBack,sections,active,onSectionChange,actions,error,fetch,children}) {
  const heading=useRef(null);
  const body=useRef(null);
  useEffect(()=>{heading.current?.focus({preventScroll:true});},[]);
  useEffect(()=>{body.current?.scrollTo({top:0,behavior:'instant'});},[active]);
  return <main className="content page-shell transaction-editor transaction-editor-page" aria-labelledby="transaction-editor-title">
    <header className="transaction-editor-heading">
      <button type="button" className="erp-form-back" onClick={onBack} disabled={busy} aria-label="Back to records"><ArrowLeft size={16}/> Back</button>
      <div className="transaction-editor-title">
        <h1 id="transaction-editor-title" tabIndex={-1} ref={heading}>{title}</h1>
        {reference&&<p>{reference}</p>}
      </div>
      <div className="transaction-editor-actions" aria-label="Document actions">
        <button type="button" className="action-pill gray" onClick={onBack} disabled={busy}>Cancel</button>
        {actions}
      </div>
    </header>
    <section className="transaction-editor-surface" aria-label="Transaction form" aria-busy={busy}>
      <div className="transaction-editor-tools">
        <ReferenceSections sections={sections} active={active} onChange={onSectionChange}/>
        {fetch}
      </div>
      {error&&<p className="transaction-editor-error" role="alert">{error}</p>}
      <div className="transaction-editor-body" ref={body} role="region" aria-label={`${active} fields`} tabIndex={0}>
        {children}
      </div>
    </section>
  </main>;
}

export function TransactionValues({label,values}) {
  const populated=values.filter(([,value])=>value!==null&&value!==undefined&&String(value).trim()!==''&&value!=='-');
  if(!populated.length)return null;
  return <dl className="transaction-values" aria-label={label}>
    {populated.map(([name,value])=><div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}
  </dl>;
}
