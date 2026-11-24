import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const src=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('login requires server-verified ERP access, not optional workflow availability',()=>{
  const match=src.match(/const establishAdminAccess=async token=>\{([\s\S]*?)\n  \};/);
  assert.ok(match,'ERP access initialization is present');
  assert.match(match[1],/await loadMyAccess\(\)/);
  assert.match(match[1],/if\(!access\?\.enabled\)throw/);
  assert.match(match[1],/try\s*\{\s*await refreshActiveWorkflow\(\)/);
  assert.match(match[1],/catch\s*\(error\)/);
  assert.match(src,/await initializeCloudStore\(token\)/);
});
test('saved passwords still use Supabase Auth and cannot skip first-login policy',()=>{
  assert.match(src,/await signInWithPassword\(email,loginValues\.password\)/);
  assert.match(src,/await getAuthUser\(token\)/);
  assert.match(src,/if\(requiresInitialPasswordChange\(identity\)\)/);
});
