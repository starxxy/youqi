const { chromium } = require('C:/Users/starynas/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const path=require('node:path');const fs=require('node:fs');const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});const context=await browser.newContext({viewport:{width:1480,height:1250},deviceScaleFactor:1});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const out=path.join(__dirname,'exports');fs.mkdirSync(out,{recursive:true});
 await page.goto('http://127.0.0.1:4173');await page.screenshot({path:path.join(out,'三方案总览.png'),fullPage:true});
 for(const v of ['a','b','c']){
  for(const p of ['today','schedule','alarms','shift','task','overdue','appearance','sync']){
   await page.goto(`http://127.0.0.1:4173/?variant=${v}&page=${p}&capture=1`);
   const frame=page.locator(`.device[data-variant=${v}]`);await frame.screenshot({path:path.join(out,`${v.toUpperCase()}-${p}.png`)});
   const overflow=await frame.locator('.mobile-main').evaluate(el=>el.scrollWidth>el.clientWidth+1);assert.equal(overflow,false,`${v}/${p} has horizontal overflow`);
  }
  await page.goto(`http://127.0.0.1:4173/?variant=${v}&mode=desktop&capture=1`);await page.locator(`.device[data-variant=${v}]`).screenshot({path:path.join(out,`${v.toUpperCase()}-desktop.png`)});
 }
 // Verify the consequential interactions, not merely whether buttons exist.
 await page.goto('http://127.0.0.1:4173/?variant=a&page=overdue');
 await page.locator('[data-variant=a] [data-action=reschedule]').first().click();
 await page.locator('[data-variant=a] input[name=due]').fill('2026-10-15');await page.locator('[data-variant=a] form').evaluate(el=>el.requestSubmit());
 let data=await page.evaluate(()=>JSON.parse(localStorage.getItem('youqi-design-v1')));assert.equal(data.tasks[0].due,'2026-10-15');assert.equal(data.tasks[0].revision,2);assert.equal(data.tasks[0].history.length,2);
 await page.goto('http://127.0.0.1:4173/?variant=a&page=task');
 const frame=page.locator('[data-variant=a]');await frame.locator('[data-action=edit-event]').click();await frame.locator('input[name=start]').fill('10:00');await frame.locator('form').evaluate(el=>el.requestSubmit());
 assert.ok((await frame.innerText()).includes('09:30 · 手机响铃'));
 await frame.locator('[data-action=add-reminder]').click();await frame.locator('select[name=anchor]').selectOption('end');await frame.locator('select[name=direction]').selectOption('1');await frame.locator('input[name=minutes]').fill('15');await frame.locator('form').evaluate(el=>el.requestSubmit());
 assert.ok((await frame.innerText()).includes('结束后 15 分钟'));
 await page.goto('http://127.0.0.1:4173/?variant=a&page=appearance');await frame.locator('[data-action=skin][data-skin=dark]').click();assert.equal(await frame.getAttribute('data-skin'),'dark');
 await page.goto('http://127.0.0.1:4173/?variant=a&page=sync');await frame.locator('[data-device=windows]').selectOption('ring');data=await page.evaluate(()=>JSON.parse(localStorage.getItem('youqi-design-v1')));assert.equal(data.devices[1].mode,'ring');
 await page.locator('[data-review-action=reset]').click();
 await page.goto('http://127.0.0.1:4173/?variant=a&page=overdue&capture=1');await frame.locator('[data-action=reschedule]').first().click();await frame.screenshot({path:path.join(out,'A-reschedule-sheet.png')});
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(out,'验证结果.json'),JSON.stringify({pageErrors:errors,screenshots:29,checks:['三方案八页面无水平溢出','改期保存日期、计数与历史','事件时间修改联动提醒','多提醒相对结束时间计算','主题切换','设备提醒策略持久化'],date:'2026-10-11'},null,2));
 await browser.close();console.log('Captured 29 screenshots. Interaction checks passed.');
})().catch(e=>{console.error(e);process.exit(1)});
