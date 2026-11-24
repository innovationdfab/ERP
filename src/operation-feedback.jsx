import React,{useEffect,useState} from 'react';
import {CheckCircle2,AlertCircle,X} from 'lucide-react';
import './operation-feedback.css';
export function OperationFeedback(){
 const [notice,setNotice]=useState(null);
 useEffect(()=>{const success=e=>setNotice({id:crypto.randomUUID(),title:e.detail.title,error:false});const error=e=>setNotice({id:crypto.randomUUID(),title:'Could not save',message:String(e.detail||'Review the error on the page.'),error:true});window.addEventListener('erp-operation-feedback',success);window.addEventListener('erp-storage-error',error);return()=>{window.removeEventListener('erp-operation-feedback',success);window.removeEventListener('erp-storage-error',error);};},[]);
 useEffect(()=>{if(!notice)return;const timer=setTimeout(()=>setNotice(null),notice.error?6000:2800);return()=>clearTimeout(timer);},[notice]);
 if(!notice)return null;const Icon=notice.error?AlertCircle:CheckCircle2;
 return <div key={notice.id} className={`operation-feedback ${notice.error?'is-error':''}`} role="status" aria-live={notice.error?'assertive':'polite'}><Icon aria-hidden="true"/><div><strong>{notice.title}</strong><small>{notice.error?notice.message:'Confirmed by the ERP database'}</small></div><button type="button" aria-label="Dismiss action feedback" onClick={()=>setNotice(null)}><X size={16}/></button><span className="operation-feedback-timer"/></div>;
}
