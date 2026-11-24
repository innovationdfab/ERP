import test from 'node:test';
import assert from 'node:assert/strict';
import { loginFailureMessage } from '../src/login-failure.js';
test('a missing ERP RPC does not invalidate successful employee credentials',()=>{
 const m=loginFailureMessage(Object.assign(new Error('Could not find the function public.erp_admin_my_access'),{status:404,code:'PGRST202'}),{credentialsVerified:true,stage:'ERP access'});
 assert.match(m,/email and password were accepted/);
 assert.match(m,/database function/);
});
test('Supabase Auth 404 suggests checking the configured project',()=>{
 assert.match(loginFailureMessage({status:404,message:'Not found'}),/VITE_SUPABASE_URL/);
});
test('missing account role cannot be bypassed',()=>{
 const m=loginFailureMessage(new Error('This account has no active ERP role.'),{credentialsVerified:true,stage:'ERP access'});
 assert.match(m,/administrator must verify/i);
});
test('original source retains permission gates',async()=>{
 const {readFileSync}=await import('node:fs');
 const s=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
 assert.match(s,/establishAdminAccess\(token\)/);
 assert.match(s,/initializeCloudStore\(token\)/);
 assert.match(s,/if\(!credentialsVerified\)localStorage.removeItem/);
});
