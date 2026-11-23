// Login-only regression with isolated authentication responses.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {chromium} from 'playwright';
const origin='https://dfab-login-fixture.supabase.co';
const server=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','5194','--strictPort'],{
 env:{...process.env,VITE_SUPABASE_URL:origin,VITE_SUPABASE_PUBLISHABLE_KEY:'fixture'},stdio:['ignore','pipe','inherit']});
let browser;
try{
 await Promise.race([once(server.stdout,'data'),once(server,'exit').then(()=>{throw new Error('Vite exited');})]);
 browser=await chromium.launch({headless:true,executablePath:process.env.ERP_CHROMIUM_PATH,args:JSON.parse(process.env.ERP_CHROMIUM_ARGS||'[]')});
 const page=await browser.newPage({viewport:{width:1440,height:950},reducedMotion:'reduce'});
 page.setDefaultTimeout(8000);
 const errors=[];page.on('pageerror',error=>errors.push(error.message));
 let attempts=0;
 await page.route(origin+'/**',async route=>{
  const endpoint=new URL(route.request().url()).pathname.split('/').at(-1);
  let body;
  if(endpoint==='token'){
   const data=route.request().postDataJSON();
   assert.equal(data.email,'qa@example.test');assert.equal(data.password,'Fixture-Password-2026');
   attempts++;
   if(attempts===1){await route.fulfill({status:400,json:{error_description:'Invalid login credentials'}});return;}
   body={access_token:'fixture',refresh_token:'fixture-refresh'};
  }else if(endpoint==='user')body={id:'fixture',email:'qa@example.test',app_metadata:{}};
  else if(endpoint==='erp_admin_my_access')body={enabled:true,is_admin:false,rights:{}};
  else if(endpoint==='erp_admin_active_workflow'||endpoint==='erp_get_ui_state')body=[];
  else throw new Error(`Unexpected ${endpoint}`);
  await route.fulfill({json:body});
 });
 await page.goto('http://127.0.0.1:5194');
 const password=page.getByLabel('Password',{exact:true});
 assert.equal(await password.isDisabled(),true);
 assert.equal(await page.getByRole('button',{name:'Show password',exact:true}).isDisabled(),true);
 await page.getByRole('button',{name:'Start welding',exact:true}).click();
 await password.fill('Fixture-Password-2026');
 await page.getByRole('button',{name:'Show password',exact:true}).click();
 assert.equal(await password.getAttribute('type'),'text');
 assert.equal(await password.inputValue(),'Fixture-Password-2026');assert.equal(attempts,0);
 await page.getByRole('button',{name:'Hide password',exact:true}).press('Space');
 assert.equal(await password.getAttribute('type'),'password');
 await page.getByRole('button',{name:'Show password',exact:true}).click();
 await page.getByRole('button',{name:'Stop welding',exact:true}).click();
 assert.equal(await password.getAttribute('type'),'password');assert.equal(await password.isDisabled(),true);
 await page.getByRole('button',{name:'Start welding',exact:true}).click();
 assert.equal(await password.inputValue(),'Fixture-Password-2026');
 for(const width of [1440,1024,768,390,320]){
  await page.setViewportSize({width,height:950});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${width}px page width`);
  const {field,button}=await page.locator('.login-password-control').evaluate(element=>({field:element.getBoundingClientRect().toJSON(),button:element.querySelector('button').getBoundingClientRect().toJSON()}));
  assert.ok(button.x>=field.x&&button.x+button.width<=field.x+field.width+1,`${width}px password icon`);
  assert.ok(button.y>=field.y&&button.y+button.height<=field.y+field.height+1,`${width}px password icon height ${JSON.stringify({field,button})}`);
  const animations=await page.locator('.weld-pass').evaluate(element=>getComputedStyle(element).animationName);
  assert.equal(animations,'none');
  if(process.env.ERP_LOGIN_SCREENSHOTS&&[1440,390].includes(width))await page.screenshot({path:`${process.env.ERP_LOGIN_SCREENSHOTS}-${width}.png`,fullPage:true,animations:'disabled'});
 }
 await page.setViewportSize({width:1440,height:950});
 await page.emulateMedia({reducedMotion:'no-preference'});
 assert.equal(await page.locator('.weld-pass').evaluate(element=>getComputedStyle(element).animationName),'login-weld-travel');
 await page.getByLabel('Email',{exact:true}).fill('qa@example.test');
 await page.getByRole('button',{name:'Login to ERP',exact:true}).click();
 await page.getByRole('alert').filter({hasText:'Incorrect email or password'}).waitFor();
 assert.equal(attempts,1);
 await page.getByRole('button',{name:'Login to ERP',exact:true}).click();
 await page.locator('.command-launcher').waitFor();
 assert.equal(attempts,2);assert.deepEqual(errors,[]);
 console.log('Verified welding activation, password visibility and keyboard control, relocking, five responsive widths, reduced motion, sign-in error and successful authentication');
}finally{await browser?.close();server.kill();}
