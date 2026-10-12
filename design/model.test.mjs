import test from 'node:test';
import assert from 'node:assert/strict';
import {overdueDays,overdueLevel,offsetTime,rescheduleTask,defaultState} from './model.js';
test('截止日不逾期；次日一级；七天后封顶但实际天数继续累计',()=>{
 assert.equal(overdueLevel('2026-10-11','2026-10-11'),0);
 assert.equal(overdueLevel('2026-10-11','2026-10-12'),1);
 assert.equal(overdueLevel('2026-10-11','2026-10-18'),7);
 assert.equal(overdueLevel('2026-10-11','2026-10-24'),7);
 assert.equal(overdueDays('2026-10-11','2026-10-24'),13);
 assert.equal(overdueLevel(undefined),0);
 assert.equal(overdueLevel('2026-10-15','2026-10-11'),0);
});
test('相对提醒处理前一天、次日和多日偏移',()=>{
 assert.equal(offsetTime('00:15',-30),'前一天 23:45');
 assert.equal(offsetTime('23:45',30),'次日 00:15');
 assert.equal(offsetTime('10:30',-30),'10:00');
 assert.equal(offsetTime('09:00',2880),'2 天后 09:00');
});
test('改期保留历史、递增计数、重算逾期且不篡改输入对象',()=>{
 const old=defaultState().tasks[0],changed=rescheduleTask(old,'2026-10-15');
 assert.equal(old.due,'2026-10-08');assert.equal(old.history.length,1);
 assert.equal(changed.revision,2);assert.equal(changed.history.length,2);
 assert.deepEqual(changed.history[1],{from:'2026-10-08',to:'2026-10-15',changedAt:'2026-10-11'});
 assert.equal(overdueLevel(changed.due),0);
});
