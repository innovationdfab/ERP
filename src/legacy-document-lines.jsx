import React from 'react';
import {Plus} from 'lucide-react';
import {InvoiceProducts,InvoiceCharges} from './invoice-line-editor.jsx';

export function LegacyDocumentLines({active,lines,totals,charges,onAdd,onChange,onCharge,onRemove,Suggest,disabled}) {
  return active==='Charges'
    ? <InvoiceCharges charges={charges} totals={totals} onChange={onCharge} disabled={disabled}/>
    : <InvoiceProducts lines={lines} totals={totals} onChange={onChange} onRemove={onRemove} Suggest={Suggest}
        disabled={disabled} legacy hideAdd={lines.length>0}
        addButton={<button type="button" className="action-pill blue" onClick={onAdd} disabled={disabled}>
          <Plus size={14}/> Add Line Item
        </button>}/>;
}
