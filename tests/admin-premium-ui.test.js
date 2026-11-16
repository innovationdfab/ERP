import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const control=readFileSync(new URL('../src/admin-control.jsx',import.meta.url),'utf8');
const main=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');

test('Premium Admin stays within existing ERP shell and exposes live data connections',()=>{
 assert.match(control,/className="content page-shell admin-root admin-simple"/);
 assert.match(control,/\['lineage','Data connections',Database\]/);
 assert.match(control,/storageCounts=\{\}/);
 assert.match(main,/storageCounts=\{Object\.fromEntries\(Object\.entries\(exportCloudSnapshot\(\)\)/);
 assert.match(control,/traceDocument\(\{page:/);
});
test('Admin data inspector is read-only; published templates use the original audited operations',()=>{
 assert.match(control,/tab==='lineage'/);
 assert.match(control,/tab==='workflows'/);
 for(const action of ['saveTemplate','publishTemplate','unpublishTemplate','loadAdminDashboard'])assert.match(control,new RegExp(`\\b${action}\\b`));
 assert.match(control,/Current catalog/);
});
test('Generic ERP editor includes remaining fields and preserves record column persistence',()=>{
 assert.match(main,/remainingFields\.filter\(field=>field!==documentId\)\.map\(recordField\)/);
 assert.match(main,/config\.columns\.map\(c=>form\[c\]/);
 assert.match(main,/erp-field-section/);
 assert.match(main,/erp-form-source-section/);
});
test('vendor invoice references read purchase invoices and manufacturing safety values stay first',()=>{
 assert.match(main,/field==='Invoice'&&title==='Vendor Payments'\?'Purchase Invoice':field/);
 assert.match(main,/label=\{field==='Invoice'&&title==='Vendor Payments'\?'Purchase Invoice':field\}/);
 const segment=main.slice(main.indexOf('const created=target.columns.map'),main.indexOf('const targetForm=recordToObject'));
 assert.ok(segment.indexOf("column==='Reject Qty'")<segment.indexOf('configuredSourceValue'));
 assert.ok(segment.indexOf('configuredSourceValue')<segment.indexOf('column===sourceField'));
});
