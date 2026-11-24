import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const admin=readFileSync(new URL('../src/admin-control.jsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../src/admin-control.css',import.meta.url),'utf8');
const api=readFileSync(new URL('../src/admin-api.js',import.meta.url),'utf8');

test('Admin workspace has a contained left panel and nested functional sections',()=>{
 assert.match(admin,/className="admin-console-sidebar"/);
 assert.match(admin,/className="admin-console-navigation"/);
 assert.match(admin,/ADMIN_DASHBOARD=\['overview','Dashboard',LayoutDashboard\]/);
 for(const label of ['Team & Access','Document Connections','Oversight'])assert.ok(admin.includes(label));
 for(const id of ['users','departments','roles','workflows','lineage','audit','storage'])assert.ok(admin.includes(`['${id}',`));
 assert.match(admin,/aria-expanded=\{Boolean\(expandedGroups\[group\.id\]\)\}/);
 assert.match(admin,/onClick=\{\(\)=>navigateTab\(id\)\}/);
 assert.match(css,/grid-template-columns:236px minmax\(0,1fr\)/);
 assert.match(css,/max-width:950px/);
});

test('employee logins are read from Supabase and Add and Edit use the same editor',()=>{
 assert.match(admin,/loadAdminDashboard\(\)/);
 assert.match(admin,/Saved logins/);
 assert.match(admin,/data\.users\.filter\(p=>/);
 assert.match(admin,/beginEmployeeInvite/);
 assert.match(admin,/selectUser\(p\)/);
 assert.match(admin,/\(inviting\|\|user\)&&<Card editor/);
 assert.match(admin,/onClick=\{inviting\?sendInvitation:saveUserForm\}/);
 assert.match(admin,/const ok=await run\(\(\)=>inviteUser\(/);
 assert.match(admin,/const ok=await run\(\(\)=>saveUser\(user\)/);
 assert.match(api,/export const inviteUser=async/);
 assert.match(api,/export const saveUser=/);
 assert.match(admin,/Active means ERP access is enabled, not that someone is currently online/);
});

test('administrator creation hides password and retains safe invitation policy',()=>{
 assert.match(admin,/isAdminRoleSelected\(invitation\.role_ids\)/);
 assert.match(admin,/const adminInvite=isAdminRoleSelected\(invitation\.role_ids\)/);
 assert.match(admin,/const password=adminInvite\?'':employeePassword\.password/);
 assert.match(admin,/Administrator accounts use personal email invitations/);
 assert.match(admin,/temporaryPasswordIssue/);
 assert.match(admin,/resetEmployeeLogin/);
});

test('Admin has in-app confirmations and animated saved/failed notices',()=>{
 assert.match(admin,/askConfirmation\(/);
 assert.match(admin,/admin-console-toast/);
 assert.match(admin,/role=\{adminNotice\.kind==='error'\?'alert':'status'\}/);
 assert.match(css,/@keyframes admin-console-toast-in/);
 assert.match(css,/prefers-reduced-motion:reduce/);
 assert.doesNotMatch(admin,/(?<![A-Za-z.])window\.(alert|confirm|prompt)\s*\(/);
});
