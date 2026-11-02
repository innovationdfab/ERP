import React from 'react';
import {transactionSection,transactionContext} from './transaction-context.js';

export function TransactionLocation({title,status}){
 const section=transactionSection(title);
 return <p className="eyebrow transaction-location"><span>Transactions</span>{section&&<><span aria-hidden="true">/</span><span>{section}</span></>}{status&&<span className="transaction-state">{status}</span>}</p>;
}
export function TransactionFlow({doc,links,documents,onOpenSource}){
 const context=transactionContext(doc,links),sourceAvailable=context.source&&documents.some(d=>d.module===context.source.module&&d.number===context.source.number),shorten=items=>items.length>2?`${items.slice(0,2).join(' / ')} +${items.length-2}`:items.join(' / ');
 return <ol className="process-stepper process-local-flow" aria-label="Transaction flow">
  <li><small>{context.source?'Source document':context.sources.length?'Fetch from':'Entry'}</small>{context.source&&sourceAvailable?<button type="button" className="link-button" aria-label={`Open source ${context.source.module} ${context.source.number}`} onClick={()=>onOpenSource(context.source)}>{context.sourceText}</button>:<strong title={context.sourceText}>{context.source?context.sourceText:context.sources.length?shorten(context.sources):'Manual entry'}</strong>}</li>
  <li aria-current="step"><small>Current document</small><strong>{doc.module}</strong>{context.process&&<span>{context.process}</span>}</li>
  <li><small>Next task</small><strong title={context.nextText}>{context.next.length?shorten(context.next):context.nextText}</strong></li>
 </ol>;
}
