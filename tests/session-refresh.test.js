import test from 'node:test';
import assert from 'node:assert/strict';
import {createSessionRefresh} from '../src/backend/session-refresh.js';
const jwt=(session,exp)=>`x.${Buffer.from(JSON.stringify({session_id:session,sub:'user1',iss:'project1',exp})).toString('base64url')}.x`;
function fixture(){
 let saved={access_token:jwt('s1',100),refresh_token:'refresh-1',expires_at:100,user:'qa@example.test'};
 let calls=0,expired=0;
 let action=async()=>({access_token:jwt('s1',4000),refresh_token:'refresh-2',expires_in:3600});
 const manager=createSessionRefresh({read:()=>saved,write:value=>saved=value,remove:()=>saved=null,notify:()=>expired++,now:()=>400000,
  refresh:async token=>{calls++;assert.equal(token,'refresh-1');return action();}});
 return {manager,get saved(){return saved;},set saved(value){saved=value;},get calls(){return calls;},get expired(){return expired;},set action(value){action=value;}};
}
test('concurrent reads and saves share one refresh and retain the rotated refresh token',async()=>{
 const f=fixture(),old=f.saved.access_token;
 const tokens=await Promise.all([f.manager.ensure(old),f.manager.ensure(old),f.manager.ensure(old)]);
 assert.equal(f.calls,1);assert.equal(new Set(tokens).size,1);
 assert.equal(f.saved.refresh_token,'refresh-2');assert.equal(f.saved.expires_at,4000);
 assert.equal(await f.manager.ensure(old),f.saved.access_token);
});
test('a valid session is kept and a rejected token can be force renewed once',async()=>{
 const f=fixture();f.saved={...f.saved,expires_at:5000};
 const old=f.saved.access_token;
 assert.equal(await f.manager.ensure(old),old);assert.equal(f.calls,0);
 assert.notEqual(await f.manager.ensure(old,{force:true}),old);assert.equal(f.calls,1);
});
test('temporary network failure preserves the session and allows later renewal',async()=>{
 const f=fixture();f.action=async()=>{throw new Error('Network unavailable');};
 await assert.rejects(f.manager.ensure(f.saved.access_token),/Network/);
 assert.ok(f.saved);assert.equal(f.expired,0);
 f.action=async()=>({access_token:'new-token',refresh_token:'new-refresh',expires_in:3600});
 assert.equal(await f.manager.ensure(f.saved.access_token),'new-token');
});
test('invalid refresh token expires the session and notifies the login screen',async()=>{
 const f=fixture();f.action=async()=>{throw Object.assign(new Error('Invalid Refresh Token: not found'),{status:400});};
 await assert.rejects(f.manager.ensure(f.saved.access_token),/Refresh Token/);
 assert.equal(f.saved,null);assert.equal(f.expired,1);
});
test('late refresh cannot restore a session after logout or overwrite another login',async()=>{
 const f=fixture();let complete;
 f.action=()=>new Promise(resolve=>complete=resolve);
 const old=f.saved.access_token;
 const result=f.manager.ensure(old);
 f.saved={access_token:jwt('other',9000),refresh_token:'different-refresh',expires_at:9000};
 complete({access_token:jwt('s1',4000),refresh_token:'refresh-2',expires_in:3600});
 await assert.rejects(result,/session changed/);
 assert.equal(f.saved.refresh_token,'different-refresh');
 assert.equal(await f.manager.ensure(old),old);
});

test('late authorization failure uses the latest token without rotating it again',async()=>{
 const f=fixture(),old=f.saved.access_token;
 const current=await f.manager.ensure(old);
 assert.equal(await f.manager.ensure(old,{force:true}),current);
 assert.equal(f.calls,1);
});
test('tabs coordinated by a lock perform one refresh and adopt the saved rotation',async()=>{
 let saved={access_token:jwt('s1',100),refresh_token:'first',expires_at:100},calls=0,queue=Promise.resolve();
 const lock=task=>{const result=queue.then(task);queue=result.catch(()=>{});return result;};
 const setup=()=>createSessionRefresh({read:()=>saved,write:value=>saved=value,remove:()=>saved=null,notify:()=>{},lock,now:()=>400000,
  refresh:async()=>{calls++;return {access_token:jwt('s1',4000),refresh_token:'second',expires_at:4000};}});
 const first=setup(),second=setup(),old=saved.access_token;
 assert.equal(new Set(await Promise.all([first.ensure(old),second.ensure(old)])).size,1);
 assert.equal(calls,1);assert.equal(saved.refresh_token,'second');
});
