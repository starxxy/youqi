const {chromium}=require('C:/Users/starynas/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const {pathToFileURL}=require('node:url');const path=require('node:path');const fs=require('node:fs');const assert=require('node:assert/strict');
(async()=>{
const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
const page=await browser.newPage({viewport:{width:1440,height:1200}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.goto(pathToFileURL(path.join(__dirname,'..','有期-UI设计.html')).href);
assert.equal(await page.locator('.device').count(),3);await page.selectOption('#page-select','overdue');assert.ok((await page.locator('[data-variant=a]').innerText()).includes('重新设置截止日期'));
await page.locator('[data-variant=a] [data-action=reschedule]').first().click();assert.equal(await page.locator('[data-variant=a] form').count(),1);await page.locator('[data-variant=a] [data-action=close-sheet]').click();
await page.goto('http://127.0.0.1:4173/?variant=a&page=task');await page.locator('[data-variant=a] [data-action=complete]').click();await page.selectOption('#page-select','alarms');assert.ok((await page.locator('[data-variant=a]').innerText()).includes('任务已完成，关联提醒停用'));
await page.locator('[data-review-action=reset]').click();
await page.setViewportSize({width:360,height:820});
for(const v of ['a','b','c'])for(const screen of ['today','schedule','alarms','shift','task','overdue','appearance','sync']){
await page.goto(`http://127.0.0.1:4173/?variant=${v}&page=${screen}`);
const overflowing=await page.locator(`[data-variant=${v}] .mobile-main`).evaluate(el=>el.scrollWidth>el.clientWidth+1);assert.equal(overflowing,false,`Narrow overflow: ${v}/${screen}`);
}
assert.deepEqual(errors,[]);
const reportPath=path.join(__dirname,'exports','验证结果.json');const report=JSON.parse(fs.readFileSync(reportPath,'utf8'));report.checks.push('离线单文件加载与改期弹层','360px 窄屏下全部页面无水平溢出','任务完成后关联闹钟显示停用','模型测试：截止日与七级封顶、跨天偏移、改期历史');fs.writeFileSync(reportPath,JSON.stringify(report,null,2),'utf8');
await browser.close();console.log('Offline delivery, narrow screens and completion/reminder consistency passed.');
})().catch(e=>{console.error(e);process.exit(1)});
