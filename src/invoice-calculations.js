/** INR/foreign-currency invoice arithmetic at two decimal precision. */
const parseNonNegative = (value, label, positive=false) => {
  const raw=String(value??'').trim();
  if(!/^\d+(?:\.\d+)?$/.test(raw))throw new Error(`${label} must be a valid non-negative number.`);
  const amount=Number(raw);
  if(!Number.isFinite(amount)||amount<0||(positive&&amount===0))throw new Error(`${label} must be ${positive?'positive':'non-negative'}.`);
  return amount;
};
const cents=value=>Math.round((value+Number.EPSILON)*100);
export function calculateInvoice(lines, taxRate){
  const tax=parseNonNegative(taxRate,'Tax (%)');
  if(tax>100)throw new Error('Tax (%) must be between 0 and 100.');
  if(!Array.isArray(lines)||lines.length===0)throw new Error('Add at least one invoice line.');
  let taxableCents=0,taxCents=0;
  const details=lines.map((line,index)=>{
    if(!String(line.code??'').trim()&&!String(line.description??'').trim())throw new Error(`Line ${index+1}: product/description is required.`);
    const quantity=parseNonNegative(line.quantity,`Line ${index+1} quantity`,true);
    const rate=parseNonNegative(line.rate,`Line ${index+1} rate`);
    const taxable=cents(quantity*rate);
    const taxAmount=Math.round((taxable*tax/100)+Number.EPSILON);
    taxableCents+=taxable;taxCents+=taxAmount;
    return {taxable:taxable/100,tax:taxAmount/100,gross:(taxable+taxAmount)/100};
  });
  return {taxable:taxableCents/100,tax:taxCents/100,total:(taxableCents+taxCents)/100,details};
}
