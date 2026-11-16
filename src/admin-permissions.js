/** Permission decisions are mirrored by database RLS/RPC checks; this is UI only. */
export const ACTIONS = ['view','create','edit','delete','approve','export'];
export const SAFE_PAGES = new Set(['Home','Workflow Guide','Change Password']);
export function canAccess(access, page, action='view') {
  if (!access || !ACTIONS.includes(action)) return false;
  if (access.is_admin) return true;
  if (action==='view' && SAFE_PAGES.has(page)) return true;
  const rights=access.rights || {};
  return Boolean(rights[page]?.[action]);
}
export function isValidEdge(edge, catalog) {
  if (!edge || !Array.isArray(catalog)) return false;
  const byName = new Map(catalog.map(item=>[item.name,item]));
  const from = byName.get(edge.source_page), to=byName.get(edge.target_page);
  if (!from || !to || !from.fields?.length || !to.fields?.length || from.name === to.name) return false;
  const mapping=edge.field_map||{};
  if (Array.isArray(mapping) || typeof mapping !== 'object' || Object.keys(mapping).length>20) return false;
  return Object.entries(mapping).every(([toField,fromField]) => to.fields.includes(toField) && from.columns.includes(fromField));
}
export function validateTemplateEdges(edges, catalog) {
  if (!Array.isArray(edges) || edges.length===0) return 'Add at least one workflow connection.';
  if (edges.length>100) return 'A template can have at most 100 connections.';
  const seen = new Set();
  const next = new Map();
  for (const edge of edges) {
    if (!isValidEdge(edge,catalog)) return `Invalid workflow connection: ${edge?.source_page||'unknown'} → ${edge?.target_page||'unknown'}.`;
    if (seen.has(edge.source_page)) return `${edge.source_page} can have only one next step in this workflow template.`;
    seen.add(edge.source_page);next.set(edge.source_page,edge.target_page);
  }
  for (const source of next.keys()) {
    const traversed = new Set();let page=source;
    while(next.has(page)) {
      if(traversed.has(page)) return 'The workflow contains a cycle. Connect steps in a forward-only sequence.';
      traversed.add(page);page=next.get(page);
    }
  }
  return '';
}
export const normalizedEdges = edges => edges.map(e=>({source_page:e.source_page,target_page:e.target_page,gate_statuses:Array.isArray(e.gate_statuses)?e.gate_statuses.filter(Boolean):[],field_map:e.field_map||{}}));
