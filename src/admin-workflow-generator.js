/**
 * Safe Admin workflow draft builder.
 *
 * Its only authority is the ERP's registered page catalog. It never creates
 * documents, changes a published template or writes to Supabase. Generated
 * steps are intentionally restricted to declared default_next relationships.
 * The database RPC remains responsible for authorization, approval gates and
 * atomic publishing.
 */
import { validateTemplateEdges } from './admin-permissions.js';

const REF_FIELDS_BY_PAIR = Object.freeze({
  'Sales Enquiries->Sales Quotations': ['Enquiry', 'Enquiry No'],
  'Sales Orders->Work Order': ['SO No', 'SO No'],
  'Work Order->Material Request': ['Work Order', 'WO No'],
  'Material Request->Material Issue': ['Work Order', 'Work Order'],
  'Material Issue->Route Cards': ['WO No', 'Work Order'],
  'Production Output->Outward QC': ['Output No', 'Output No'],
  'Purchase Orders->GRN': ['PO No', 'PO No'],
  'GRN->Inward QC': ['GRN No', 'GRN No'],
  'Purchase->Vendor Payments': ['Invoice', 'Invoice No'],
  'Service Invoice->Vendor Payments': ['Invoice', 'Invoice No'],
  'Outsource Issue DC->Outsource Receipt': ['Issue DC', 'DC No'],
  'Job Work Inward->Job Work Return DC': ['Inward No', 'Inward No'],
  'Jobwork Material Issue->Jobwork Material Receipt': ['Issue No', 'Issue No'],
  'Jobwork Material Receipt->Job Work QC': ['Receipt No', 'Receipt No'],
  'Project Planning->Project Order': ['Project No', 'Project No'],
  'Excess Issue->Input to Production': ['Issue No', 'Issue No'],
});
const NEVER_COPY = /^(status|stage|decision|approved by|created by|reviewed by|inspector|good qty|reject qty|completed qty|accepted qty|rejected qty|consumed qty|received qty|amount|taxable amount|rate|total)$/i;
const text = value => String(value ?? '').trim();
const names = value => Array.isArray(value) ? value.map(text).filter(Boolean) : [];

/** Accept either the local JSON catalog or the live Supabase admin catalog. */
export function normalizeWorkflowCatalog(catalog=[]) {
  return (Array.isArray(catalog) ? catalog : []).map(item => ({
    name:text(item.page ?? item.name),
    group:text(item.module_group ?? item.group),
    columns:names(item.columns),
    fields:names(item.fields),
    statuses:names(item.statuses),
    next:text(item.default_next ?? item.next),
    defaultGates:names(item.default_gate_statuses),
  })).filter(entry=>entry.name);
}

/** Only copy existing compatible source fields. Never guess amounts or output quantities. */
export function inferSafeFieldMap(source, destination) {
  if (!source || !destination) return {};
  const columns = new Set(source.columns);
  const writable = new Set(destination.fields);
  const map = {};
  const [toRef, fromRef] = REF_FIELDS_BY_PAIR[`${source.name}->${destination.name}`] || [];
  if (toRef && writable.has(toRef) && columns.has(fromRef) && toRef !== destination.columns[0]) map[toRef] = fromRef;
  for (const field of destination.fields) {
    if (Object.keys(map).length >= 20) break;
    // Target's first column is usually its newly generated document number.
    if (field === destination.columns[0] || NEVER_COPY.test(field)) continue;
    if (columns.has(field) && !Object.hasOwn(map,field)) map[field] = field;
  }
  return map;
}

/** Build a complete editable draft from *declared* ERP links, never from speculative processes. */
export function generateRegisteredFlows(catalog=[]) {
  const normalized=normalizeWorkflowCatalog(catalog);
  const byName=new Map(normalized.map(x=>[x.name,x]));
  const edges=[];
  const skipped=[];
  for (const source of normalized) {
    if (!source.next) continue; // Masters, reports and terminal documents are not automatic transactions.
    const dest=byName.get(source.next);
    if (!dest || !source.fields.length || !dest.fields.length || source.name===dest.name) {
      skipped.push({source:source.name,target:source.next,reason:'Missing or non-transaction destination'});
      continue;
    }
    // Live catalog may specify server-validated gates. Never invent or weaken them.
    const gateStatuses=source.defaultGates.filter(status=>source.statuses.includes(status)).slice(0,20);
    const invalidGates=source.defaultGates.filter(status=>!source.statuses.includes(status));
    if (invalidGates.length) {
      skipped.push({source:source.name,target:source.next,reason:`Invalid registered gate: ${invalidGates.join(', ')}`});
      continue;
    }
    edges.push({source_page:source.name,target_page:dest.name,gate_statuses:gateStatuses,field_map:inferSafeFieldMap(source,dest)});
  }
  edges.sort((a,b)=>a.source_page.localeCompare(b.source_page));
  const error=edges.length?validateTemplateEdges(edges,normalized):'No registered transaction connections found.';
  return {
    edges:error?[]:edges,
    skipped,
    error,
    totalDefined:normalized.filter(x=>x.next).length,
    matchedFields:edges.reduce((sum,x)=>sum+Object.keys(x.field_map).length,0),
    groups:[...new Set(edges.map(x=>byName.get(x.source_page)?.group).filter(Boolean))],
  };
}
