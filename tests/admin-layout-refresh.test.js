import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const main=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
const admin=readFileSync(new URL('../src/admin-control.jsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../src/admin-control.css',import.meta.url),'utf8');

test('Admin entry appears directly before global Search and opens existing Admin route',()=>{
 const header=main.slice(main.indexOf('<div className="top-actions premium-actions">'),main.indexOf('<button className="top-icon-btn"'));
 assert.ok(header.includes('erp-top-admin-btn'));
 assert.ok(header.indexOf('erp-top-admin-btn')<header.indexOf('global-search'));
 assert.match(header,/onClick=\{\(\)=>goToPage\('Admin Control'\)\}/);
 assert.match(header,/aria-label="Open Admin Control section"/);
});
test('Admin sections are grouped with practical hints and clear navigation',()=>{
 for(const section of ['overview','users','departments','roles','workflows','lineage','audit','storage']) {
  assert.ok(admin.includes(`['${section}','`),`Missing Admin tab ${section}`);
 }
 assert.match(admin,/ADMIN_NAV_GROUPS/);
 assert.match(admin,/admin-console-sidebar/);
 assert.match(admin,/admin-console-submenu/);
 assert.match(css,/independently scrolling content/);
});
test('Changes keep database-backed admin actions and safety gates intact',()=>{
 for(const fn of ['loadAdminDashboard','saveDepartment','saveRole','saveUser','inviteUser','publishTemplate','deleteRole','deleteDepartment','askConfirmation']) assert.ok(admin.includes(fn));
 assert.match(main,/if\(activePage==='Admin Control'&&!ctx\.adminAccess\?\.is_admin\)/);
});
