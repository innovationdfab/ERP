import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=file=>readFileSync(new URL(file,import.meta.url),'utf8');
const jsx=read('../src/admin-control.jsx');
const css=read('../src/admin-control.css');
const api=read('../src/admin-api.js');
const edge=read('../supabase/functions/erp-admin-invite/index.ts');
test('Admin sidebar remains in view and main Admin content scrolls independently on desktop',()=>{
 assert.match(css,/height:calc\(100dvh - 116px\)/);
 assert.match(css,/\.admin-console-navigation\{overflow-y:auto/);
 assert.match(css,/\.admin-console-content\{[\s\S]*?overflow-y:auto/);
 assert.match(css,/@media\(max-width:950px\)/);
});
test('Admin navigation retains all existing screens but eliminates duplicate dashboard cards',()=>{
 for(const name of ['users','departments','roles','workflows','lineage','audit','storage'])assert.match(jsx,new RegExp(`\\['${name}','`));
 assert.doesNotMatch(jsx,/className="admin-action-grid"/);
 assert.doesNotMatch(jsx,/className="admin-guided-setup"/);
});
test('Admin API reports failing endpoint without retrying writes automatically',()=>{
 assert.match(api,/explainAdminNetworkFailure/);
 assert.match(api,/erp-admin-invite/);
 assert.match(api,/refresh Saved logins/);
 assert.doesNotMatch(api,/setTimeout\(.*inviteUser/);
});
test('Admin login Edge Function keeps origin allowlist and emits visible forbidden response',()=>{
 assert.match(edge,/allowedOrigins\.includes\(origin\)/);
 assert.match(edge,/status: 403, headers: \{ \.\.\.headers, 'Access-Control-Allow-Origin': origin \}/);
 assert.match(edge,/if \(request\.method === 'OPTIONS'\)/);
});
