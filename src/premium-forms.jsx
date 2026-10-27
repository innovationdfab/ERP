import React, {useEffect, useId, useRef, useState} from 'react';
import {UploadCloud, FileText, FileSpreadsheet, Image as ImageIcon, CheckCircle2, X, RefreshCw, ArrowUpRight, Download, ArrowLeft, LoaderCircle, Layers3} from 'lucide-react';
import {createPortal} from 'react-dom';
import {parseCsv} from './erp-utils.js';

const sizeLabel = bytes => bytes < 1024*1024 ? `${Math.max(1,Math.round(bytes/1024))} KB` : `${(bytes/(1024*1024)).toFixed(1)} MB`;

export function FormDialogBackdrop({children,...props}){return createPortal(<div {...props}>{children}</div>,document.body);}

export function FormSectionHeading({title,description,icon:Icon=Layers3}){
  return <div className="premium-section-heading"><span className="premium-section-icon"><Icon size={20}/></span><div><h2>{title}</h2>{description&&<p>{description}</p>}</div></div>;
}

/** A single-file selector. Selection invokes the caller's existing save/import flow. */
export function PremiumUploadField({label='Attachment',value,onSelect,accept='.png,.jpg,.jpeg,.webp,.gif,.pdf,.txt,.csv',maxBytes=1024*1024,hint,compact=false,disabled=false}){
  const id=useId(),inputRef=useRef(null),sequence=useRef(0),dragDepth=useRef(0);
  const [dragging,setDragging]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[preview,setPreview]=useState('');
  const name=typeof value==='string'?value:value?.name;
  const image=value?.dataUrl?.startsWith('data:image/')||value?.type?.startsWith('image/');
  useEffect(()=>{if(value instanceof File&&value.type.startsWith('image/')){const url=URL.createObjectURL(value);setPreview(url);return()=>URL.revokeObjectURL(url)}setPreview(value?.dataUrl?.startsWith('data:image/')?value.dataUrl:'')},[value]);
  const choose=async files=>{
    const token=++sequence.current;
    setError('');setDragging(false);dragDepth.current=0;
    if(files.length!==1){setError('Choose one file at a time.');return}
    const file=files[0],rules=accept.split(',').map(x=>x.trim().toLowerCase());
    const supported=rules.some(rule=>rule.startsWith('.')?file.name.toLowerCase().endsWith(rule):rule.endsWith('/*')?file.type.startsWith(rule.slice(0,-1)):file.type===rule);
    if(!supported){setError(`Unsupported file. Choose ${accept.replaceAll(',',' / ')}.`);return}
    if(!file.size){setError('This file is empty. Choose a file with content.');return}
    if(file.size>maxBytes){setError(`File is too large. The limit is ${sizeLabel(maxBytes)}.`);return}
    setBusy(true);
    try{await onSelect(file)}catch(err){if(token===sequence.current)setError(err.message||'Could not read this file. Try again.')}
    finally{if(token===sequence.current)setBusy(false);if(inputRef.current)inputRef.current.value=''}
  };
  const clear=async()=>{setError('');setBusy(true);try{await onSelect(null);if(inputRef.current)inputRef.current.value=''}catch(err){setError(err.message||'Could not remove this file.')}finally{setBusy(false)}};
  return <div className={`premium-upload-field ${compact?'is-compact':''}`}>
    <input ref={inputRef} id={id} className="premium-file-input" type="file" accept={accept} aria-label={label} aria-describedby={`${id}-hint${error?` ${id}-error`:''}`} disabled={disabled||busy} onChange={e=>{if(e.target.files?.length)choose(Array.from(e.target.files))}}/>
    <div className={`premium-dropzone ${dragging?'is-dragging':''} ${error?'has-error':''} ${name?'has-file':''}`} aria-busy={busy}
      onDragEnter={e=>{e.preventDefault();if(disabled||busy)return;dragDepth.current++;setDragging(true)}}
      onDragOver={e=>e.preventDefault()}
      onDragLeave={e=>{e.preventDefault();dragDepth.current=Math.max(0,dragDepth.current-1);if(!dragDepth.current)setDragging(false)}}
      onDrop={e=>{e.preventDefault();if(!disabled&&!busy)choose(Array.from(e.dataTransfer.files))}}>
      <span className="premium-upload-symbol">{busy?<LoaderCircle size={25} className="premium-spinner"/>:image?<ImageIcon size={25}/>:<UploadCloud size={25}/>}</span>
      <strong>{busy?'Reading your file…':dragging?'Drop your file here':name?'File selected':'Drag & drop your file'}</strong>
      <p>{name?'Replace it here, or remove it below.':'or browse files on your device'}</p>
      <button type="button" className="premium-browse" disabled={disabled||busy} onClick={e=>{e.preventDefault();inputRef.current?.click()}}>{name?<RefreshCw size={14}/>:<UploadCloud size={14}/>} {name?'Replace file':'Choose file'}</button>
      <small id={`${id}-hint`}>{hint||`${accept.replaceAll('.','').replaceAll(',',' · ').toUpperCase()} · Up to ${sizeLabel(maxBytes)}`}</small>
    </div>
    {name&&<div className="premium-selected-file">{preview?<img src={preview} alt={`Preview of ${name}`}/>:<span className="premium-file-symbol">{name.toLowerCase().endsWith('.csv')?<FileSpreadsheet size={22}/>:<FileText size={22}/>}</span>}<div><b title={name}>{name}</b><small>{value?.size?`${sizeLabel(value.size)} · `:''}{value?.dataUrl?'Attachment ready':'Selected file'}</small></div><CheckCircle2 size={17} className="premium-file-check"/><button type="button" title={`Remove ${label}`} aria-label={`Remove ${label}`} disabled={disabled||busy} onClick={e=>{e.preventDefault();clear()}}><X size={16}/></button></div>}
    {error&&<p id={`${id}-error`} className="premium-upload-error" role="alert">{error}</p>}
  </div>;
}

export function PremiumImportPage({title,onClose,onImport,columns,onDownloadTemplate}){
  const [file,setFile]=useState(null),[rows,setRows]=useState([]),[busy,setBusy]=useState(false),[error,setError]=useState('');
  const select=async candidate=>{setError('');if(!candidate){setFile(null);setRows([]);return}const parsed=parseCsv((await candidate.text()).replace(/^\uFEFF/,''));if(parsed.length<2)throw new Error('Add at least one data row below the header before importing.');setFile(candidate);setRows(parsed)};
  const upload=async()=>{if(!file||busy)return;setError('');setBusy(true);try{await onImport(file)}catch(err){setError(err.message||'Import failed. Check the template and try again.')}finally{setBusy(false)}};
  const product=title.includes('BOM')?'Bill of materials':'Products';
  return <main className="content page-shell premium-form-page premium-import-page"><div className="page-title-row"><div><span className="premium-page-eyebrow">DATA IMPORT</span><h1>{product} upload</h1><p className="page-subtitle">Bring your records in with a clear, reviewable CSV import.</p></div><button type="button" className="action-pill gray" onClick={onClose} disabled={busy}><ArrowLeft size={15}/> Close</button></div>
    <div className="premium-import-layout"><section className="card premium-import-main"><FormSectionHeading title="Upload your file" description="Choose a CSV exported from Excel, then review its contents." icon={UploadCloud}/><PremiumUploadField label="Import CSV" value={file} onSelect={select} accept=".csv" maxBytes={10*1024*1024} disabled={busy} hint="CSV format · Maximum 10 MB · One file at a time"/>
      {file&&<div className="premium-import-review"><div className="premium-preview-heading"><div><span className="premium-status-dot"/> Ready to review</div><span>{rows.length-1} data row{rows.length===2?'':'s'} · {rows[0].length} columns</span></div><div className="table-wrap premium-preview-table" tabIndex={0} aria-label="CSV preview"><table><thead><tr>{rows[0].map((cell,i)=><th key={i}>{cell||`Column ${i+1}`}</th>)}</tr></thead><tbody>{rows.slice(1,6).map((row,i)=><tr key={i}>{rows[0].map((_,j)=><td key={j}>{row[j]||'—'}</td>)}</tr>)}</tbody></table></div><p>Preview shows up to 5 rows. All {rows.length-1} data rows are included in this import.</p></div>}
      {error&&<p className="premium-upload-error" role="alert">{error}</p>}
      <div className="premium-import-footer"><span><CheckCircle2 size={15}/> Review your file before importing</span><button type="button" className="action-pill blue" disabled={!file||busy} onClick={upload}>{busy?<LoaderCircle size={16} className="premium-spinner"/>:<ArrowUpRight size={16}/>} {busy?'Importing…':'Import records'}</button></div>
    </section><aside className="premium-import-aside"><section className="card premium-template-card"><span className="premium-template-icon"><FileSpreadsheet size={26}/></span><span className="premium-page-eyebrow">START WITH THE RIGHT FORMAT</span><h2>Use the import template</h2><p>Keep the columns in the same order. Fill in your records in Excel and save the sheet as CSV.</p><button type="button" className="premium-template-download" onClick={onDownloadTemplate}><Download size={16}/> Download Format</button></section><section className="card premium-column-card"><h3>Template columns</h3><ol>{columns.map((column,i)=><li key={column}><span>{String(i+1).padStart(2,'0')}</span>{column}</li>)}</ol></section></aside></div>
  </main>;
}
