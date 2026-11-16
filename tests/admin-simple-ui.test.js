import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const control=readFileSync(new URL('../src/admin-control.jsx',import.meta.url),'utf8');
const preview=readFileSync(new URL('../src/admin-preview.jsx',import.meta.url),'utf8');
const shell=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');

test('Admin Control opens on a simple overview and all administration areas remain reachable',()=>{
 assert.match(shell,/initialTab=\{activePage==='Users'\?'users':activePage==='User Roles'\|\|activePage==='Role Permissions'\?'roles':'overview'\}/);
 for(const section of ['overview','users','departments','roles','workflows','audit','storage']){
  assert.ok(control.includes(`['${section}','`),`Missing ${section} section`);
 }
 assert.match(control,/tab==='overview'/);
 assert.match(control,/admin-action-grid/);
});

test('people, roles, departments and workflow CRUD still point to database operations',()=>{
 for(const fn of ['saveDepartment','saveRole','saveUser','inviteUser','saveTemplate','publishTemplate','unpublishTemplate','registerStorage','deleteDraftTemplate','deleteDepartment','deleteRole','unmapStorage']){
  assert.match(control,new RegExp(`\\b${fn}\\b`));
 }
 assert.match(control,/if\(!await askConfirmation\(/);
});

test('signed out admin preview exposes no employee data or database mutation',()=>{
 assert.match(preview,/if\(publicMode\) return/);
 assert.match(preview,/No company database information is exposed/);
 assert.doesNotMatch(preview,/admin-api\.js|loadAdminDashboard\(|inviteUser\(|saveDepartment\(/);
});

test('technical options remain available but collapsed by default',()=>{
 assert.match(control,/<details className="admin-edge-details">/);
 assert.match(control,/<details className="admin-advanced-details">/);
 assert.match(control,/aria-label="Admin sections"/);
 assert.match(control,/role=\{type==='error'\?'alert':'status'\}/);
});
