/** Read-only explanation of the actual ERP catalog. This never grants permissions or writes data. */
const unique = items => [...new Set(items.filter(Boolean))];
// Existing storage exceptions in main.jsx: these are aliases, not new collections.
const specialSections = {
  'Sales Invoice':['dfab-erp-sales-invoices-v2'],
  'Production BOM':['dfab-erp-production-bom-v2'],
  'Route Card':['dfab-erp-route-card-v2'],
  'List':['dfab-erp-products-v3'],
  'Groups':['dfab-erp-product-groups-v2'],
  'Customers':['dfab-erp-customers-v2'],
  'Vendors':['dfab-erp-vendors-v2'],
};
// Registered reports also read these sources in main.jsx/reportRowsFromDatabase.
const builtInReportSources = {
  'Purchase Orders':['Purchase Order Register','Pending Purchase Order to GRN','Pending Purchase Indent for order'],
  'GRN':['GRN Register','Pending Purchase Indent For GR'],
  'Inward QC':['Inward QC Register'],
  'Purchase':['Purchase Invoice Register','Purchase Invoice Itemwise Register','Pending Payables'],
  'Sales Enquiries':['Enquiry Register','Pending Enquiry For QUotation'],
  'Sales Quotations':['Sales Quotation Register','Sales Quotation Register Headerwise'],
  'Sales Orders':['Sales Order Register','Sales Order Created & Closed','Sales Order Created & Closed Headerwise','Pending Sales Order for Work Order','Pending Sales Order for Invoice'],
  'Sales Invoice':['Sales Register','Sales Register Headerwise','Pending Receivables'],
  'Credit Note':['Credit Note Register'],
  'Proforma Invoice':['Proforma Invoice Register'],
  'Delivery Challan':['DC Register','DC Register Headerwise'],
  'Work Order':['Work Order Register','Pending Work Order for Production Output'],
  'Outsource Issue DC':['Outsource DC Register','Outsource DC Register Headerwise','Outsource DC Register Created to Closed'],
  'Outsource Receipt':['Outsource Receipt Register'],
  'Rejection Note':['Rejection Note Register'],
  'Job Work Inward':['Jobwork Inward Register'],
  'Vendor Payments':['Vendor Payment History'],
  'List':['Regular Stock List','Stock Ledger','Stock Report','Groupwise Stock Report','Product Rack List'],
};
const string = value => String(value ?? '').trim();

export function fieldTransfers(from, to, fieldMap = {}) {
  if (!from || !to) return [];
  const available = new Set(from.columns || []);
  const targets = new Set(to.fields || []);
  const explicit = Object.entries(fieldMap || {}).filter(([target, source]) => targets.has(target) && available.has(source))
    .map(([target, source]) => ({source, target, kind:'configured'}));
  const already = new Set(explicit.map(item => item.target));
  const sameName = (to.fields || []).filter(field => available.has(field) && !already.has(field) && !/^(status|stage|decision)$/i.test(field))
    .map(field => ({source:field, target:field, kind:'same-name'}));
  return [...explicit, ...sameName];
}

export function traceDocument({page, catalog=[], edges=[], storage=[], counts={}, reports={}}) {
  const entry = catalog.find(item => item.page === page);
  if (!entry) return null;
  const links = edges.filter(edge => edge.source_page === page).map(edge => {
    const destination = catalog.find(item => item.page === edge.target_page);
    return {
      ...edge,
      destination: edge.target_page,
      destinationGroup: destination?.module_group || '',
      transfers: fieldTransfers(entry, destination, edge.field_map),
    };
  });
  const key = `dfab-erp-${page}`;
  const stores = unique([key, ...(specialSections[page]||[]), ...storage.filter(item => item.page === page).map(item => item.storage_key)])
    .filter(candidate => Object.hasOwn(counts, candidate) || storage.some(item => item.storage_key === candidate))
    .map(candidate => ({key:candidate, count:Number.isFinite(counts[candidate]) ? counts[candidate] : null}));
  const reportNames=new Set(catalog.map(item=>item.page));
  const reporting=unique([...Object.entries(reports).filter(([,def]) => def?.source === page).map(([title]) => title),...(builtInReportSources[page]||[]).filter(name=>reportNames.has(name))]);
  return {
    page,
    group: entry.module_group,
    fields:entry.fields || [],
    columns:entry.columns || [],
    stores,
    links,
    reports:reporting,
    destinations:unique(links.map(link => link.destination)),
  };
}

/** Form layout only: order and stored column names remain untouched. */
export function groupDocumentFields(fields=[]) {
  const grouped = [
    {key:'references',title:'Document & linked references',caption:'Document numbers and source records'},
    {key:'parties',title:'Parties & item details',caption:'Existing customer, supplier, product and process information'},
    {key:'quantities',title:'Quantity & commercial details',caption:'Amounts, material quantities and financial values'},
    {key:'schedule',title:'Dates & execution',caption:'Scheduling, quality checks and responsible teams'},
    {key:'other',title:'Additional details',caption:'Other fields required by this ERP document'},
  ].map(section => ({...section, fields:[]}));
  for (const field of fields) {
    const name=string(field).toLowerCase();
    let key='other';
    if (/(^|\s)(no\.?|number|ref|reference|invoice|indent|receipt|issue dc|work order|so|po|grn|bom|project)(\s|$)/i.test(name) || /code$/.test(name)) key='references';
    else if (/vendor|customer|supplier|product|material|item|warehouse|store|machine|operation|process|transport|delivery channel|service|description/i.test(name)) key='parties';
    else if (/qty|quantity|rate|amount|total|price|value|tax|discount|currency|cost|uom|balance/i.test(name)) key='quantities';
    else if (/date|due|delivery|planned|target|owner|inspector|approved|department|status|stage|disposition|reason|remark|note/i.test(name)) key='schedule';
    grouped.find(section => section.key === key).fields.push(field);
  }
  return grouped.filter(section => section.fields.length);
}

export function configuredSourceValue(source, field, mapping) {
  const sourceField = mapping?.[field];
  return sourceField && Object.hasOwn(source, sourceField) ? source[sourceField] : undefined;
}
