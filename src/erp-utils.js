import { readCloudValue, writeCloudValue } from './backend/cloud-store.js';
/** Shared, framework-independent ERP data rules. */
export const todayISO = () => new Date().toLocaleDateString('en-CA', {timeZone:'Asia/Kolkata'});
export function isoDate(value) {
  if (!value || value === '-') return '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const match = String(value).match(/^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/);
  if (!match) return '';
  const month = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(match[2].toLowerCase());
  return month < 0 ? '' : `${match[3]}-${String(month+1).padStart(2,'0')}-${match[1].padStart(2,'0')}`;
}
export const displayDate = value => {const date=isoDate(value);return date?new Date(`${date}T12:00:00`).toLocaleDateString('en-GB',{day:'2-digit',month:'short',year:'numeric'}).replaceAll(' ','-'):value;};
export function readStored(key, fallback) {
  return readCloudValue(key, fallback);
}
export function writeStored(key,value) {
  return writeCloudValue(key, value);
}
export function fieldType(label) {
  if (/date|delivery|due|valid until/i.test(label)) return 'date';
  if (/qty|quantity|amount|rate|value|price|percent|GST %/i.test(label)) return 'number';
  return 'text';
}
export function validateFields(fields, values) {
  for (const label of fields) {
    const value=String(values[label]??'').trim();
    if (!value || value==='-') return `${label} is required.`;
    if (fieldType(label)==='number' && (!Number.isFinite(Number(value)) || Number(value)<0 || (/qty|quantity/i.test(label)&&!/reject|completed|good/i.test(label)&&Number(value)===0))) return `${label} must be a valid ${/qty|quantity/i.test(label)?'positive':'non-negative'} number.`;
    if (fieldType(label)==='date' && !isoDate(value)) return `Enter a valid ${label.toLowerCase()}.`;
  }
  return '';
}
export function parseCsv(text) {
  const rows=[];let row=[],cell='',quoted=false;
  for(let i=0;i<text.length;i++) {const ch=text[i];if(ch==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++;}else quoted=!quoted;}else if(ch===','&&!quoted){row.push(cell.trim());cell='';}else if((ch==='\n'||ch==='\r')&&!quoted){if(ch==='\r'&&text[i+1]==='\n')i++;row.push(cell.trim());if(row.some(Boolean))rows.push(row);row=[];cell='';}else cell+=ch;}
  if(quoted)throw new Error('CSV contains an unclosed quotation mark.');row.push(cell.trim());if(row.some(Boolean))rows.push(row);return rows;
}
export const csvCell = value => `"${(/^[\s]*[=+@-]/.test(String(value??''))?"'":'')+String(value??'').replaceAll('"','""')}"`;
export function validateBackup(data) {
  if (!data || typeof data.records!=='object' || Array.isArray(data.records)||data.records===null) throw new Error('This is not a DFAB ERP backup.');
  const entries=Object.entries(data.records);
  if(!entries.length)throw new Error('This backup has no records.');
  if(entries.some(([key])=>!key.startsWith('dfab-')||/session|password|credential/i.test(key)))throw new Error('Backup contains unsupported or session-related keys.');
  return entries;
}
export async function readAttachment(file) {
  if(!file)return null;
  if(file.size>1024*1024)throw new Error('Select a file of 1 MB or less for this local workspace.');
  if(!/\.(png|jpe?g|webp|gif|pdf|txt|csv)$/i.test(file.name))throw new Error('Use PNG, JPEG, WebP, GIF, PDF, TXT or CSV.');
  return new Promise((resolve,reject)=>{const reader=new FileReader();reader.onerror=()=>reject(new Error('Could not read the file.'));reader.onload=()=>resolve({name:file.name,dataUrl:reader.result});reader.readAsDataURL(file)});
}
