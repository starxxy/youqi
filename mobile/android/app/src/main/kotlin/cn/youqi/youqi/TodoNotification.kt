package cn.youqi.youqi

import android.app.*
import android.content.*
import android.os.Build
import org.json.JSONObject
import java.time.*
import java.time.temporal.ChronoUnit

/** Device-local preference; desktop sync must not enable notifications on other devices. */
object TodoNotification {
    const val ID=702
    private const val CHANNEL="youqi_today_v1"
    data class Item(val id:String,val title:String,val date:LocalDate,val due:LocalDate?)
    internal fun items(root:JSONObject,today:LocalDate):List<Item> {
        val occurrences=root.optJSONObject("occurrences")?:JSONObject()
        val result=mutableListOf<Item>()
        for(task in AlarmHub.jsonList(root.optJSONArray("tasks")?:org.json.JSONArray())) {
            if(!task.isNull("deletedAt"))continue
            val id=task.optString("id");val title=task.optString("title")
            val start=runCatching{LocalDate.parse(task.getString("startDate"))}.getOrNull()?:continue
            val repeat=task.optString("repeat","none")
            val end=if(repeat=="none")minOf(start,today) else today
            val hasInstance=occurrences.keys().asSequence().any{occurrences.optJSONObject(it)?.optString("taskId")==id}
            var date=if(repeat=="none") {if(hasInstance)end.plusDays(1) else start}
                else maxOf(start,runCatching{LocalDate.parse(task.getString("generatedThrough")).plusDays(1)}.getOrDefault(start))
            while(!date.isAfter(end)) {
                val matches=when(repeat){
                    "daily"->true
                    "weekly"->task.optJSONArray("weekdays")?.let{a->(0 until a.length()).any{a.optInt(it)==date.dayOfWeek.value}}==true
                    "interval"->ChronoUnit.DAYS.between(start,date)%task.optInt("interval",1).coerceAtLeast(1)==0L
                    else->date==start
                }
                if(matches) {
                    val key="$id@$date";val o=occurrences.optJSONObject(key)
                    if(o==null || (!o.optBoolean("done") && o.isNull("deletedAt"))) {
                        val due=if(o!=null)runCatching{LocalDate.parse(o.getString("dueDate"))}.getOrNull()
                            else runCatching{LocalDate.parse(task.getString("dueDate"))}.getOrNull()?.let{if(repeat=="none")it else date.plusDays(ChronoUnit.DAYS.between(start,it))}
                        result.add(Item(key,title,date,due))
                    }
                }
                date=date.plusDays(1)
            }
            // Keep already-created instances when a task's repeat rule is subsequently edited.
            for(key in occurrences.keys()) {
                val o=occurrences.optJSONObject(key)?:continue
                if(o.optString("taskId")!=id || o.optBoolean("done") || !o.isNull("deletedAt") || result.any{it.id==key})continue
                val d=runCatching{LocalDate.parse(o.getString("date"))}.getOrNull()?:continue
                if(d<=today)result.add(Item(key,title,d,runCatching{LocalDate.parse(o.getString("dueDate"))}.getOrNull()))
            }
        }
        return result.sortedWith(compareBy<Item>{if(it.due!=null && it.due<today)it.due else LocalDate.MAX}.thenBy{it.date})
    }
    private fun rollover(c:Context)=PendingIntent.getBroadcast(c,0,Intent(c,TodoNotificationReceiver::class.java)
        .setAction("cn.youqi.TODO_ROLLOVER"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun setEnabled(c:Context,enabled:Boolean) {
        check(AlarmHub.prefs(c).edit().putBoolean("todoPinned",enabled).commit()){"保存通知设置失败"}
        refresh(c)
    }
    fun refresh(c:Context) {
        val nm=c.getSystemService(NotificationManager::class.java)
        val manager=c.getSystemService(AlarmManager::class.java)
        if(!AlarmHub.prefs(c).getBoolean("todoPinned",false)) {nm.cancel(ID);manager.cancel(rollover(c));return}
        val today=Instant.now(AlarmHub.clock).atZone(ZoneId.systemDefault()).toLocalDate()
        // An inexact midnight refresh is sufficient for a silent daily summary.
        val midnight=today.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        manager.setWindow(AlarmManager.RTC_WAKEUP,midnight,15*60_000L,rollover(c))
        nm.createNotificationChannel(NotificationChannel(CHANNEL,"今日待办常驻通知",NotificationManager.IMPORTANCE_LOW).apply{
            description="静默显示当前未完成事项";setSound(null,null);enableVibration(false)
        })
        if(!nm.areNotificationsEnabled() || (Build.VERSION.SDK_INT>=33 && c.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED))return
        val list=items(AlarmHub.state(c),today)
        val text=if(list.isEmpty())"今天的待办已完成" else list.take(5).joinToString("\n"){"• ${it.title}"}+(if(list.size>5)"\n另有 ${list.size-5} 项，点击查看" else "")
        val open=PendingIntent.getActivity(c,702,Intent(c,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification=Notification.Builder(c,CHANNEL).setSmallIcon(R.drawable.ic_alarm)
            .setContentTitle("今日待办 · ${list.size} 项未完成").setContentText(if(list.isEmpty())text else list.take(5).joinToString("、"){it.title})
            .setStyle(Notification.BigTextStyle().bigText(text)).setContentIntent(open).setOngoing(true)
            .setOnlyAlertOnce(true).setShowWhen(false).setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PRIVATE).build()
        nm.notify(ID,notification)
    }
}
class TodoNotificationReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        val work=goAsync();Thread{try{synchronized(AlarmHub){TodoNotification.refresh(context)}}finally{work.finish()}}.start()
    }
}
