import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {requiresInitialPasswordChange, initialPasswordIssue} from '../src/login-policy.js';

const root=new URL('..',import.meta.url).pathname;
const read=path=>readFileSync(join(root,path),'utf8');

test('only server-controlled Auth app_metadata triggers first-password setup',()=>{
 assert.equal(requiresInitialPasswordChange({app_metadata:{erp_initial_password_pending:true}}),true);
 assert.equal(requiresInitialPasswordChange({user_metadata:{erp_initial_password_pending:true}}),false);
 assert.equal(requiresInitialPasswordChange({app_metadata:{erp_initial_password_pending:false}}),false);
 assert.equal(requiresInitialPasswordChange(null),false);
});
test('employees must choose a strong matching personal password',()=>{
 assert.match(initialPasswordIssue('dfabsspl','dfabsspl'),/12/);
 assert.match(initialPasswordIssue('ProperNew2026Password','different'),/match/);
 assert.equal(initialPasswordIssue('ProperNew2026Password','ProperNew2026Password'),'');
});
test('Admin has explicit create, individual reset and confirmation-protected bulk initialization',()=>{
 const ui=read('src/admin-control.jsx');
 const api=read('src/admin-api.js');
 for(const method of ['resetEmployeeLogin','resetEmployeeLogins'])assert.match(api,new RegExp(`export const ${method}=`));
 assert.match(ui,/askConfirmation\(`Set the configured temporary password/);
 assert.match(ui,/askConfirmation\(`Replace the passwords for/);
 assert.match(ui,/isAdminEmployee\(p\)/);
 assert.match(ui,/Initialize team logins/);
});
test('service role and initial password are not exposed by any Vite client module',()=>{
 const server=read('supabase/functions/erp-admin-invite/index.ts');
 const client=read('src/main.jsx')+'\n'+read('src/admin-control.jsx')+'\n'+read('src/admin-api.js');
 assert.match(server,/Deno\.env\.get\('ERP_INITIAL_PASSWORD'\)/);
 assert.match(server,/elevated\.auth\.admin\.createUser/);
 assert.match(server,/elevated\.auth\.admin\.updateUserById/);
 assert.match(server,/caller\.rpc\('erp_admin_is_admin'\)/);
 assert.match(server,/actor\.app_metadata\?\.\[initialFlag\] !== true/);
 assert.doesNotMatch(client,/dfabsspl|SUPABASE_SERVICE_ROLE_KEY|VITE_SUPABASE_SERVICE_ROLE/);
});
test('temporary password session is blocked by Supabase RLS org and ERP role helpers',()=>{
 const sql=read('supabase/ERP_INITIAL_LOGIN_PASSWORD_POLICY.sql');
 assert.match(sql,/CREATE OR REPLACE FUNCTION public\.erp_current_org_id\(\)/i);
 assert.match(sql,/auth\.jwt\(\)->'app_metadata'->>'erp_initial_password_pending'/);
 assert.match(sql,/CREATE OR REPLACE FUNCTION public\.erp_has_permission\(p_permission text\)/i);
 assert.match(sql,/public\.erp_current_org_id\(\) IS NOT NULL/i);
 assert.doesNotMatch(sql,/DROP TABLE|TRUNCATE|DELETE FROM|insert into public\.erp_user_roles/i);
});
test('sign-in and refresh both check initial-password flag before reading ERP data',()=>{
 const main=read('src/main.jsx');
 assert.equal((main.match(/if\(requiresInitialPasswordChange\(identity\)\)/g)||[]).length,2);
 assert.match(main,/await getAuthUser\(auth\.access_token\)/);
 assert.match(main,/await getAuthUser\(token\)/);
 assert.match(main,/action:'change-initial-password'/);
 assert.match(main,/if\(!authenticated && passwordSetup\)return/);
});
