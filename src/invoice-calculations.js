/** INR/foreign-currency invoice arithmetic at two decimal precision. */
const parseNonNegative = (value, label, positive=false) => {
  const raw=String(value??'').trim();
  if(!/^\d+(?:\.\d+)?$/.test(raw))throw new Error(`${label} must be a valid non-negative number.`);
  const amount=Number(raw);
  if(!Number.isFinite(amount)||amount<0||(positive&&amount===0))throw new Error(`${label} must be ${positive?'positive':'non-negative'}.`);
  return amount;
};
const cents=value=>Math.round((value+Number.EPSILON)*100);
export const invoiceTaxFields = [['cgst','CGST'],['sgst','SGST'],['igst','IGST']];
export const invoiceChargeFields = [['freight','Freight Charges'],['packing','Loading and Packing Charges'],['insurance','Insurance Charges'],['tcs','TCS Charges']];
export const invoiceExpenseFields = [['mpt','MPT Charges'],['ut','UT Charges'],['pickling','Pickling Charges'],['buffing','Buffing Charges'],['dp','DP Charges'],['rt','RT Charges'],['transport','Transportation Charges']];
const percentage=(value,label)=>{
  const result=parseNonNegative(value,label);
  if(result>100)throw new Error(`${label} must be between 0 and 100.`);
  return result;
};
export function calculateInvoice(lines, taxRate, charges={}, expenses={}){
  const tax=parseNonNegative(taxRate,'Tax (%)');
  if(tax>100)throw new Error('Tax (%) must be between 0 and 100.');
  if(!Array.isArray(lines)||lines.length===0)throw new Error('Add at least one invoice line.');
  let taxableCents=0,taxCents=0, discountCents=0;
  const splitCents={cgst:0,sgst:0,igst:0};
  const details=lines.map((line,index)=>{
    if(!String(line.code??'').trim()&&!String(line.description??'').trim())throw new Error(`Line ${index+1}: product/description is required.`);
    const quantity=parseNonNegative(line.quantity,`Line ${index+1} quantity`,true);
    const rate=parseNonNegative(line.rate,`Line ${index+1} rate`);
    const base=cents(quantity*rate);
    if(!Number.isSafeInteger(base))throw new Error(`Line ${index+1} amount is too large.`);
    const discount=Math.round(base*percentage(line.discount||'0',`Line ${index+1} discount`)/100);
    const taxable=base-discount;
    const hasSplit=invoiceTaxFields.some(([key])=>String(line[key]??'').trim()!=='');
    const split={cgst:0,sgst:0,igst:0};
    if(hasSplit){
      const rates=Object.fromEntries(invoiceTaxFields.map(([key,label])=>[key,percentage(line[key]||'0',`Line ${index+1} ${label}`)]));
      if((rates.cgst||rates.sgst)&&rates.igst)throw new Error(`Line ${index+1}: use either CGST/SGST or IGST.`);
      if(rates.cgst+rates.sgst>100)throw new Error(`Line ${index+1}: combined CGST and SGST cannot exceed 100%.`);
      for(const [key] of invoiceTaxFields){
        split[key]=Math.round(taxable*rates[key]/100);
        splitCents[key]+=split[key];
      }
    }
    const taxAmount=hasSplit?split.cgst+split.sgst+split.igst:Math.round(taxable*tax/100+Number.EPSILON);
    discountCents+=discount;
    taxableCents+=taxable;
    taxCents+=taxAmount;
    return {discount:discount/100,taxable:taxable/100,tax:taxAmount/100,gross:(taxable+taxAmount)/100,
      cgst:split.cgst/100,sgst:split.sgst/100,igst:split.igst/100};
  });
  const gross=taxableCents+taxCents;
  const addOns=Object.fromEntries(invoiceChargeFields.map(([key,label])=>{
    const amount=parseNonNegative(charges[key]?.amount||'0',`Charges: ${label}`);
    const rate=percentage(charges[key]?.percent||'0',`Charges: ${label} %`);
    if(amount&&rate)throw new Error(`Charges: enter an amount or a percentage for ${label}.`);
    return [key,amount?cents(amount):Math.round(taxableCents*rate/100)];
  }));
  const roundOff=String(charges.roundOff??'').trim()||'0';
  if(!/^[+-]?\d+(?:\.\d{1,2})?$/.test(roundOff))throw new Error('Charges: enter a valid round-off amount.');
  const total=gross+Object.values(addOns).reduce((sum,amount)=>sum+amount,0)+cents(Number(roundOff));
  const expenseTotal=invoiceExpenseFields.reduce((sum,[key,label])=>sum+cents(parseNonNegative(expenses[key]||'0',`External expenses: ${label}`)),0);
  if(total<0||!Number.isSafeInteger(total)||!Number.isSafeInteger(expenseTotal))throw new Error('Charges: invoice or expense total is out of range.');
  return {taxable:taxableCents/100,tax:taxCents/100,total:total/100,details,discount:discountCents/100,gross:gross/100,
    cgst:splitCents.cgst/100,sgst:splitCents.sgst/100,igst:splitCents.igst/100,expenseTotal:expenseTotal/100,
    charges:Object.fromEntries(Object.entries(addOns).map(([key,value])=>[key,value/100]))};
}
