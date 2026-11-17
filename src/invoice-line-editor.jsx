import React from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { invoiceChargeFields, invoiceExpenseFields, invoiceTaxFields } from './invoice-calculations.js';

const fields=[['code','Product Code'],['description','Description'],['quantity','Quantity'],['uom','UOM'],['rate','Rate'],['discount','Disc %']];
const amount=value=>value?.toFixed(2)??'—';

export function InvoiceProducts({lines,totals,onAdd,onRemove,onChange,Suggest,disabled,legacy=false,hideAdd=false,addButton}) {
  return <section className="reference-panel invoice-form-card">
    <div className="invoice-lines-head"><h2 className="transaction-section-heading">Products</h2>
      {!hideAdd&&(addButton||<button type="button" className="action-pill blue" onClick={onAdd} disabled={disabled}><Plus size={15}/> Add Line Item</button>)}</div>
    <div className="table-wrap" tabIndex={0} aria-label="Invoice line items">
      <table className="invoice-product-grid">
        <thead><tr>{['Actions','Sl.No.',...fields.map(([,label])=>label),'Disc Amt.','Taxable Amt.',...invoiceTaxFields.flatMap(([,label])=>[`${label} %`,`${label} Amt.`]),'Gross Amt.'].map(label=><th scope="col" key={label}>{label}</th>)}</tr></thead>
        <tbody>{lines.map((line,index)=>{
          const computed=totals?.details[index];
          return <tr key={index}><td><button type="button" className="line-remove" aria-label={`Remove line ${index+1}`}
              disabled={disabled||(!legacy&&lines.length===1)} onClick={()=>onRemove(index)}><Trash2 size={14}/></button></td><td>{index+1}</td>
            {fields.map(([key,label])=><td key={key}>{React.createElement(Suggest,{
              label:key==='code'?'Product Code':label,ariaLabel:`Line ${index+1} ${label}`,disabled,
              value:line[key]??'',type:['code','description','uom'].includes(key)?'text':'number',
              min:0,step:'any',onChange:event=>onChange(index,key,event.target.value)
            })}</td>)}
            <td>{amount(computed?.discount)}</td><td>{amount(computed?.taxable)}</td>
            {invoiceTaxFields.map(([key,label])=><React.Fragment key={key}><td>
              <input aria-label={`Line ${index+1} ${label} %`} type="number" min="0" max="100" step="any" disabled={disabled}
                value={line[key]??''} onChange={event=>onChange(index,key,event.target.value)}/>
              </td><td>{amount(computed?.[key])}</td></React.Fragment>)}
            <td>{amount(computed?.gross)}</td>
          </tr>;
        })}</tbody>
      </table>
    </div>
    {!legacy&&<p className="invoice-editor-help">Blank line tax fields use the invoice Tax (%) setting.</p>}
  </section>;
}

export function InvoiceCharges({charges,totals,onChange,disabled}) {
  return <section className="reference-panel invoice-form-card">
    <h2 className="transaction-section-heading">Charges and deductions</h2>
    <div className="table-wrap" tabIndex={0} aria-label="Invoice charges">
      <table><thead><tr><th scope="col">Charge</th><th scope="col">% of taxable amount</th><th scope="col">Fixed amount</th><th scope="col">Applied amount</th></tr></thead>
        <tbody>{invoiceChargeFields.map(([key,label])=><tr key={key}><th scope="row">{label}</th>
          <td><input aria-label={`${label} percentage`} type="number" min="0" max="100" step="any" disabled={disabled}
            value={charges[key]?.percent??''} onChange={event=>onChange(key,'percent',event.target.value)}/></td>
          <td><input aria-label={`${label} amount`} type="number" min="0" step="0.01" disabled={disabled}
            value={charges[key]?.amount??''} onChange={event=>onChange(key,'amount',event.target.value)}/></td>
          <td>{amount(totals?.charges[key])}</td></tr>)}
          <tr><th scope="row">Round Off Amount</th><td>—</td><td>
            <input aria-label="Round Off Amount" type="number" step="0.01" disabled={disabled}
              value={charges.roundOff??''} onChange={event=>onChange('roundOff',null,event.target.value)}/>
          </td><td>{charges.roundOff||'—'}</td></tr>
        </tbody>
      </table>
    </div>
    <p className="invoice-editor-help">Use a percentage or a fixed amount for each charge. A negative round-off deducts from the total.</p>
  </section>;
}

export function InvoiceExpenses({expenses,onChange,disabled}) {
  return <section className="reference-panel invoice-form-card">
    <h2 className="transaction-section-heading">External Expenses</h2>
    <div className="invoice-form-grid">{invoiceExpenseFields.map(([key,label])=><label key={key}><span>{label}</span>
      <input type="number" min="0" step="0.01" disabled={disabled} value={expenses[key]??''}
        onChange={event=>onChange(key,event.target.value)}/></label>)}</div>
    <p className="invoice-editor-help">External expenses are tracked separately from the customer’s invoice total.</p>
  </section>;
}
