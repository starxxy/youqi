export const TODAY = '2026-10-11';
export const STORAGE_KEY = 'youqi-design-v1';
export const revisionHues = ['blue', 'violet', 'teal', 'rose', 'amber'];
export const overdueTones = ['#e7aeb0','#d98e95','#c96d7b','#b65165','#9c3d55','#802b46','#632037'];
export function overdueDays(due, today = TODAY) {
  if (!due) return 0;
  return Math.max(0, Math.floor((Date.parse(today + 'T00:00:00Z') - Date.parse(due + 'T00:00:00Z')) / 86400000));
}
export function overdueLevel(due, today = TODAY) { return Math.min(7, overdueDays(due, today)); }
export function dateLabel(date) { return date ? `${Number(date.slice(5,7))} 月 ${Number(date.slice(8,10))} 日` : '不设截止日期'; }
export function offsetTime(time, offset) {
  const [h,m] = time.split(':').map(Number), total=h*60+m+offset;
  const dayOffset=Math.floor(total/1440), normalized=((total%1440)+1440)%1440;
  const prefix=dayOffset===-1?'前一天 ':dayOffset===1?'次日 ':dayOffset<0?`${Math.abs(dayOffset)} 天前 `:dayOffset>0?`${dayOffset} 天后 `:'';
  return `${prefix}${String(Math.floor(normalized/60)).padStart(2,'0')}:${String(normalized%60).padStart(2,'0')}`;
}
export function rescheduleTask(task, newDate) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(newDate) || !Number.isFinite(Date.parse(newDate+'T00:00:00Z'))) throw new Error('请选择有效日期');
  return {...task, due:newDate, revision:task.revision+1, history:[...task.history,{from:task.due,to:newDate,changedAt:TODAY}]};
}
export function defaultState() {
 return {
  tasks:[
   {id:'prototype',title:'完成产品原型',description:'整理核心页面，确认任务与闹钟之间的操作路径。',type:'persistent',start:'2026-10-06',due:'2026-10-08',estimate:3,revision:1,done:false,history:[{from:'2026-10-07',to:'2026-10-08',changedAt:'2026-10-07'}]},
   {id:'review',title:'整理本周工作记录',description:'回顾本周进展，记下下周最重要的三件事。',type:'persistent',start:TODAY,due:TODAY,estimate:1,revision:0,done:false,history:[]},
   {id:'reading',title:'阅读 20 分钟',description:'读完一个小章节，留下两句读书笔记。',type:'daily',start:TODAY,due:TODAY,estimate:1,revision:0,done:false,history:[]},
   {id:'walk',title:'傍晚散步',description:'离开屏幕，出去走一走。',type:'daily',start:TODAY,due:TODAY,estimate:1,revision:0,done:false,history:[]},
   {id:'inbox',title:'整理收件箱',description:'把需要处理的邮件整理成待办。',type:'persistent',start:TODAY,due:TODAY,estimate:1,revision:0,done:true,history:[]}
  ],
  events:[{id:'e1',taskId:'prototype',start:'09:00',end:'10:30',reminders:[{id:'r1',anchor:'start',offset:-30},{id:'r2',anchor:'end',offset:-30}]},{id:'e2',taskId:'review',start:'11:00',end:'11:40',reminders:[{id:'r3',anchor:'start',offset:0}]},{id:'e3',taskId:'reading',start:'14:00',end:'14:20',reminders:[]},{id:'e4',taskId:'walk',start:'17:30',end:'18:00',reminders:[]}],
  alarms:[{id:'a1',time:'07:00',title:'起床，慢慢开始今天',rule:'周一至周五',kind:'weekly',enabled:true,snooze:5,maxSnoozes:3,duration:60,vibrate:true,tone:'晨光'},{id:'a2',time:'08:30',title:'准备开始产品原型',rule:'事件开始前 30 分钟',kind:'event',eventId:'e1',reminderId:'r1',enabled:true,snooze:5,maxSnoozes:3,duration:60,vibrate:true,tone:'清铃'},{id:'a3',time:'15:00',title:'起身喝水',rule:'15:00—18:00，每隔 60 分钟',kind:'window',enabled:false,snooze:5,maxSnoozes:3,duration:30,vibrate:true,tone:'水滴'},{id:'a4',time:'06:30',title:'晨间拉伸',rule:'从 10 月 11 日起，每隔 2 天',kind:'interval',enabled:true,snooze:10,maxSnoozes:2,duration:60,vibrate:false,tone:'晨光'}],
  shift:{anchor:'2026-10-11',enabled:true,days:[{label:'早班',times:['07:00']},{label:'早班',times:['06:00']},{label:'休息',times:[]}]},
  skins:{a:'light',b:'light',c:'dark'},materials:{a:'glass',b:'glass',c:'glass'},devices:[{id:'phone',name:'我的手机',platform:'Android',mode:'ring',current:true},{id:'windows',name:'工作电脑',platform:'Windows',mode:'notify',current:false},{id:'mac',name:'个人电脑',platform:'macOS',mode:'silent',current:false}],syncEnabled:false
 };
}
