// Open all reachable create forms and their sections using an isolated admin fixture.
import assert from 'node:assert/strict';
import {launchFixture} from './browser-fixture.mjs';
const fixture=await launchFixture(5192);
const {page,errors,open}=fixture;
const coverage=[];
try{
 await page.locator('.command-launcher').click();
 const routes=[...new Set(await page.locator('.command-text b').allTextContents())];
 await page.keyboard.press('Escape');
 for(const route of routes){
  await open(route);
  const creates=page.getByRole('button',{name:/^(Create|Add New|Add Task Entry|Add reorder policy|Add follow-up)/}).filter({visible:true});
  if(!await creates.count())continue;
  const names=await Promise.all((await creates.all()).map(async button=>(await button.getAttribute('aria-label'))||(await button.getAttribute('title'))||(await button.innerText())));
  for(const name of [...new Set(names.map(text=>text.trim()).filter(Boolean))]){
   await open(route);
   const trigger=page.getByRole('button',{name,exact:true}).first();
   if(!await trigger.isEnabled())continue;
   await trigger.click();
   const fields=await page.locator('.premium-form-page input,.premium-form-page select,.premium-form-page textarea,.transaction-editor-page input,.transaction-editor-page select,.transaction-editor-page textarea,.erp-modal input,.erp-modal textarea,.erp-modal select,.extension-editor input,.extension-editor select,.extension-editor textarea').count();
   assert.ok(fields>0,`${route} ${name} must open editable fields`);
   const sections=page.locator('nav[aria-label="Form sections"] button');
   for(const section of await sections.all()){
    await section.click();
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${route} ${name} desktop`);
   }
   await page.setViewportSize({width:390,height:844});
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${route} ${name} mobile`);
   await page.setViewportSize({width:1440,height:1000});
   const cancel=page.getByRole('button',{name:/^(Cancel|Back to records|Close)$/}).filter({visible:true});
   if(await cancel.count())await cancel.last().click();else await page.keyboard.press('Escape');
   assert.deepEqual(errors,[]);
   coverage.push({route,action:name,fields});
   console.log('PASS FORM',route,name,fields);
  }
 }
 console.log(`Verified ${coverage.length} create forms and their accessible sections across ${routes.length} menu pages on desktop and mobile.`);
}finally{await fixture.close();}
