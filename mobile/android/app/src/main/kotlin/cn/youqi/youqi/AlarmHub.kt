package cn.youqi.youqi

import android.app.*
import android.content.*
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import org.json.JSONArray
import org.json.JSONObject
import java.time.*
import java.util.UUID

object AlarmHub {
    internal var clock: Clock = Clock.systemDefaultZone()
    const val CHANNEL = "youqi_alarms_v1"
    fun prefs(c: Context) = c.getSharedPreferences("youqi", Context.MODE_PRIVATE)
    fun state(c: Context): JSONObject = JSONObject(prefs(c).getString("state", "{}")!!)
    private fun array(c: Context, key: String) = JSONArray(prefs(c).getString(key, "[]")!!)
    fun jsonList(a: JSONArray): List<JSONObject> = (0 until a.length()).map { a.getJSONObject(it) }
    fun strings(a: JSONArray?): List<String> = if (a == null) emptyList() else (0 until a.length()).map { a.getString(it) }
    @Synchronized fun log(c: Context, title: String, action: String) {
        val list = array(c, "history")
        list.put(JSONObject().put("title", title).put("action", action).put("at", Instant.now().toString()))
        val bounded = JSONArray((maxOf(0,list.length()-300) until list.length()).map { list.get(it) })
        prefs(c).edit().putString("history", bounded.toString()).commit()
    }
    fun history(c: Context): List<Map<String, Any>> = jsonList(array(c,"history")).map { mapOf("title" to it.optString("title"),"action" to it.optString("action"),"at" to it.optString("at")) }
    fun channel(c: Context) {
        val nm = c.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL,"有期闹钟",NotificationManager.IMPORTANCE_HIGH).apply {
            description="用户设置的闹钟与待办提醒"; setSound(null,null); enableVibration(false); lockscreenVisibility=Notification.VISIBILITY_PUBLIC
        })
    }
    fun exact(c: Context) = Build.VERSION.SDK_INT < 31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    private fun pending(c: Context,record: JSONObject): PendingIntent = PendingIntent.getBroadcast(c,0,
        Intent(c,AlarmReceiver::class.java).setAction("cn.youqi.FIRE")
            .setData(Uri.parse("youqi://delivery/${Uri.encode(record.getString("fireKey"))}"))
            .putExtra("key",record.getString("key")).putExtra("fireKey",record.getString("fireKey")),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancelLegacy(c:Context,key:String) {
        val intent=Intent(c,AlarmReceiver::class.java).setAction("cn.youqi.FIRE").setData(Uri.parse("youqi://fire/${Uri.encode(key)}"))
        val old=PendingIntent.getBroadcast(c,0,intent,PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)?:return
        c.getSystemService(AlarmManager::class.java).cancel(old);old.cancel()
    }
    private fun parseRule(j: JSONObject): AlarmRule {
        val type = j.optString("type","daily")
        val cycle = j.optJSONArray("days")?.let { a -> (0 until a.length()).map { i -> strings(a.getJSONObject(i).optJSONArray("times")).map(LocalTime::parse) } } ?: emptyList()
        val exceptions = j.optJSONObject("exceptions")?.let { x -> x.keys().asSequence().associate { d -> LocalDate.parse(d) to strings(x.optJSONArray(d)).map(LocalTime::parse) } } ?: emptyMap()
        val weekdays = j.optJSONArray("weekdays")?.let { x -> (0 until x.length()).map { x.getInt(it) }.toSet() } ?: (1..7).toSet()
        return AlarmRule(key=j.getString("key"),type=type,start=LocalDate.parse(j.optString("startDate",LocalDate.now().toString())),time=LocalTime.parse(j.optString("time","07:00")),
            weekdays=weekdays,intervalDays=j.optInt("interval",1).coerceIn(1,365),windowEnd=LocalTime.parse(j.optString("windowEnd","18:00")),intervalMinutes=j.optInt("intervalMinutes",60).coerceIn(1,1440),
            offsetMinutes=j.optInt("offset",0),dayOffset=j.optInt("dayOffset",0),excluded=strings(j.optJSONArray("excludedDates")).map(LocalDate::parse).toSet(),cycle=cycle,exceptions=exceptions,
            zone=if(j.optBoolean("fixedZone",false))ZoneId.of(j.optString("timeZone","Asia/Shanghai"))else ZoneId.systemDefault())
    }
    @Synchronized fun reconcile(c: Context,after: Instant = Instant.now(clock)): Int {
        channel(c)
        val root=state(c);val mode=root.optString("deviceMode","ring")
        val manager=c.getSystemService(AlarmManager::class.java)
        // A due broadcast may still be waiting for its worker while Flutter saves or refreshes.
        // Keep immutable deliveries separate from the next occurrence of each repeating rule.
        val previous=(jsonList(array(c,"deliveries"))+jsonList(array(c,"scheduled"))).associateBy { it.getString("fireKey") }
        val desired=linkedMapOf<String,JSONObject>()
        val skipped=strings(array(c,"skipped")).toSet()+strings(array(c,"fired")).toSet()
        val shotIds=jsonList(array(c,"oneShots")).map {it.getString("fireKey")}.toSet()
        if(mode!="silent") {
            for((id,record) in previous) {
                val due=record.optLong("fireAt")
                val isShot=record.optBoolean("standalone")||record.has("parentKey")
                if(id !in skipped && valid(c,record) && (!isShot || id in shotIds) && due<=after.toEpochMilli()) {
                    if(due>=after.minusSeconds(15*60).toEpochMilli())desired[id]=record
                    else log(c,record.optString("title"),"错过提醒超过15分钟，未补响")
                }
            }
            for (rule in jsonList(root.optJSONArray("nativeRules")?:JSONArray())) {
                if(!rule.optBoolean("enabled",true))continue
                try {
                    val fire=RuleEngine.next(parseRule(rule),after,skipped)?:continue
                    if(!valid(c,rule))continue
                    desired[fire.fireKey]=JSONObject(rule.toString()).put("fireAt",fire.at.toEpochMilli()).put("fireKey",fire.fireKey).put("attempt",0).put("signature",rule.toString().hashCode()).put("baseDate",fire.baseDate.toString())
                } catch(e: Exception){log(c,rule.optString("title"),"规则无法调度：${e.message}")}
            }
            val oneShots=jsonList(array(c,"oneShots")).filter { it.optLong("fireAt")>=after.minusSeconds(15*60).toEpochMilli() && it.getString("fireKey") !in skipped && valid(c,it) }
            prefs(c).edit().putString("oneShots",JSONArray(oneShots).toString()).commit()
            for (shot in oneShots) desired.putIfAbsent(shot.getString("fireKey"),shot)
        }
        // Persist before arming: delivery can occur immediately for a recently due reminder.
        check(prefs(c).edit().putString("deliveries",JSONArray(desired.values.toList()).toString()).commit()){"保存闹钟登记失败"}
        for ((id,record) in previous) {
            cancelLegacy(c,record.getString("key"))
            if(id !in desired){val operation=pending(c,record);manager.cancel(operation);operation.cancel()}
        }
        val successful=JSONArray()
        for (record in desired.values) {
            try {
                if(exact(c)){
                    val view=PendingIntent.getActivity(c,0,Intent(c,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    val trigger=maxOf(record.getLong("fireAt"),record.optLong("retryAt"),after.toEpochMilli()+100)
                    // Re-register even unchanged entries: force-stop can remove the system timer.
                    manager.setAlarmClock(AlarmManager.AlarmClockInfo(trigger,view),pending(c,record))
                    successful.put(record)
                }
            }catch(e:SecurityException){log(c,record.optString("title"),"精确闹钟权限未开启")}
        }
        prefs(c).edit().putString("scheduled",successful.toString()).commit()
        AlarmService.reconcileActive(c)
        // A notification permission/channel problem must not break alarm scheduling or snooze.
        try{TodoNotification.refresh(c)}catch(e:Exception){log(c,"待办通知","刷新失败：${e.javaClass.simpleName}")}
        return successful.length()
    }
    fun valid(c:Context,payload:JSONObject):Boolean {
        val root=state(c)
        if(root.optString("deviceMode","ring")=="silent")return false
        val occurrence=payload.optString("occurrenceId")
        if(occurrence.isNotEmpty()) {
            val o=root.optJSONObject("occurrences")?.optJSONObject(occurrence)?:return false
            if(o.optBoolean("done") || !o.isNull("deletedAt"))return false
            val t=jsonList(root.optJSONArray("tasks")?:JSONArray()).firstOrNull{it.optString("id")==o.optString("taskId")}?:return false
            if(!t.isNull("deletedAt"))return false
        }
        val parent=payload.optString("parentKey").ifEmpty { payload.optString("key") }
        if(payload.optBoolean("standalone",false))return true
        val rule=jsonList(root.optJSONArray("nativeRules")?:JSONArray()).firstOrNull { it.optString("key")==parent && it.optBoolean("enabled",true) }?:return false
        return payload.optInt("signature",rule.toString().hashCode())==rule.toString().hashCode()
    }
    @Synchronized fun fire(c: Context,key:String,deliveryId:String?=null) {
        val record=jsonList(array(c,"deliveries")).firstOrNull {
            it.optString("key")==key && (deliveryId==null || it.optString("fireKey")==deliveryId) && it.optLong("fireAt")<=clock.millis()+1000
        }?:return
        if(record.optLong("fireAt")>clock.millis()+1000)return
        if(record.optLong("retryAt")>clock.millis())return
        if(!valid(c,record)) { reconcile(c); return }
        val fireKey=record.getString("fireKey");val fired=strings(array(c,"fired"))
        if(fireKey in fired) return
        val intent=Intent(c,AlarmService::class.java).setAction("ring").putExtra("payload",record.toString())
        try { c.startForegroundService(intent) }catch(e:Exception){
            log(c,record.optString("title"),"启动响铃失败，1分钟后重试：${e.javaClass.simpleName}")
            record.put("retryAt",clock.millis()+60_000)
            val retained=jsonList(array(c,"deliveries")).map{if(it.optString("fireKey")==fireKey)record else it}
            prefs(c).edit().putString("deliveries",JSONArray(retained).toString()).putString("scheduled","[]").commit()
            reconcile(c);return
        }
        prefs(c).edit().putString("fired",JSONArray((fired+fireKey).takeLast(2000)).toString())
            .putString("oneShots",JSONArray(jsonList(array(c,"oneShots")).filter { it.optString("fireKey")!=fireKey }).toString()).commit()
        log(c,record.optString("title"),"触发")
        reconcile(c)
    }
    @Synchronized fun oneShot(c:Context,input:JSONObject) {
        check(exact(c)){"请先允许精确闹钟权限"}
        val key=input.optString("key","test:${UUID.randomUUID()}")
        val time=Instant.now(clock).plusSeconds(input.optLong("seconds",10).coerceAtLeast(1))
        val shot=JSONObject(input.toString()).put("key",key).put("fireAt",time.toEpochMilli()).put("fireKey","$key@${time.toEpochMilli()}").put("standalone",true).put("attempt",0)
        val list=jsonList(array(c,"oneShots")).filter { it.optString("key")!=key }+shot
        prefs(c).edit().putString("oneShots",JSONArray(list).toString()).commit();reconcile(c)
    }
    @Synchronized fun cancelShot(c:Context,key:String){
        prefs(c).edit().putString("oneShots",JSONArray(jsonList(array(c,"oneShots")).filter { it.optString("key")!=key && it.optString("parentKey")!=key }).toString()).commit()
        AlarmService.cancelKey(key);reconcile(c)
    }
    @Synchronized fun snooze(c:Context,payload:JSONObject,minutes:Int?=null):Boolean {
        val ring=payload.optJSONObject("ring")?:JSONObject();val attempt=payload.optInt("attempt",0)
        if(!exact(c)||!valid(c,payload))return false
        val manual=minutes!=null
        if(!AlarmPolicy.canSnooze(manual,attempt,ring.optInt("maxSnoozes",3))){log(c,payload.optString("title"),"已达自动重响次数上限");return false}
        val parent=payload.optString("parentKey").ifEmpty {payload.getString("key")}
        val cycle=payload.optString("cycleId").ifEmpty{payload.getString("fireKey")}
        val key="snooze:$parent:$cycle"
        val delay=AlarmPolicy.delayMinutes(minutes,ring.optInt("snooze",5))
        val at=AlarmPolicy.fireAt(clock.millis(),delay)
        val count=payload.optInt("snoozeCount",payload.optInt("attempt",0)).coerceAtLeast(0).coerceAtMost(1_000_000)+1
        val shot=JSONObject(payload.toString()).put("key",key).put("parentKey",parent).put("cycleId",cycle).put("fireAt",at).put("fireKey","$key@$at").put("attempt",if(manual)attempt else attempt+1).put("snoozeCount",count)
        val list=jsonList(array(c,"oneShots")).filter { it.optString("key")!=key }+shot
        check(prefs(c).edit().putString("oneShots",JSONArray(list).toString()).commit()){"保存延后提醒失败"}
        reconcile(c)
        if(jsonList(array(c,"scheduled")).none{it.optString("fireKey")==shot.optString("fireKey")})return false
        log(c,payload.optString("title"),"延后 $delay 分钟，第 $count 次");return true
    }
    @Synchronized fun skipNext(c:Context,payload:JSONObject){
        val parent=payload.optString("parentKey").ifEmpty{payload.optString("key")}
        val next=jsonList(array(c,"scheduled")).firstOrNull{it.optString("key")==parent}?:return
        val skipped=(strings(array(c,"skipped"))+next.getString("fireKey")).takeLast(2000)
        prefs(c).edit().putString("skipped",JSONArray(skipped).toString()).commit();reconcile(c)
    }
    @Synchronized fun disable(c:Context,payload:JSONObject){
        val root=state(c);val kind=payload.optString("sourceKind");val sourceId=payload.optString("sourceId");val parent=payload.optString("parentKey").ifEmpty{payload.optString("key")}
        var entity:JSONObject?=null;var entityType=""
        val list=if(kind=="alarm")root.optJSONArray("alarms")else if(kind=="shift")root.optJSONArray("shifts")else null
        if(list!=null){entity=jsonList(list).firstOrNull{it.optString("id")==sourceId};entity?.put("enabled",false);entityType=kind}
        if(kind=="task"){
            val candidates=if(parent.startsWith("block:"))jsonList(root.optJSONArray("blocks")?:JSONArray())else jsonList(root.optJSONArray("tasks")?:JSONArray())
            for(candidate in candidates){for(r in jsonList(candidate.optJSONArray("reminders")?:JSONArray())){
                val candidateKey=if(parent.startsWith("block:"))"block:${candidate.optString("id")}:${r.optString("id")}" else "task:${candidate.optString("id")}:${r.optString("id")}"
                if(candidateKey==parent){r.put("enabled",false);entity=candidate;entityType=if(parent.startsWith("block:"))"timeBlock" else "task"}
            }}
        }
        for(r in jsonList(root.optJSONArray("nativeRules")?:JSONArray()))if(r.optString("key")==parent||(kind in listOf("alarm","shift")&&r.optString("sourceId")==sourceId))r.put("enabled",false)
        if(entity!=null){
            entity.put("updatedAt",Instant.now().toString()).put("updatedByDeviceId",root.optString("deviceId"))
            val outbox=root.optJSONArray("outbox")?:JSONArray();outbox.put(JSONObject().put("mutationId",UUID.randomUUID().toString()).put("entityType",entityType).put("entityId",entity.optString("id")).put("baseRevision",entity.opt("revision")?:JSONObject.NULL).put("operation","upsert").put("originatingDeviceId",root.optString("deviceId")).put("payload",JSONObject(entity.toString())));root.put("outbox",outbox)
        }
        root.put("nativeGeneration",root.optInt("nativeGeneration",0)+1)
        val overrides=root.optJSONArray("nativeOverrides")?:JSONArray();overrides.put(JSONObject().put("parent",parent).put("sourceKind",kind).put("sourceId",sourceId));root.put("nativeOverrides",overrides)
        prefs(c).edit().putString("state",root.toString()).commit();reconcile(c)
    }
    fun status(c: Context):Map<String,Any> {
        val nm=c.getSystemService(NotificationManager::class.java);val pm=c.getSystemService(PowerManager::class.java)
        val next=jsonList(array(c,"scheduled")).minByOrNull { it.optLong("fireAt",Long.MAX_VALUE) }
        val label=next?.let{val dt=Instant.ofEpochMilli(it.getLong("fireAt")).atZone(ZoneId.systemDefault());"下一次 ${dt.monthValue} 月 ${dt.dayOfMonth} 日 ${dt.toLocalTime()} · ${it.optString("title")}"}?:"暂无已登记的未来闹钟"
        val upcoming=jsonList(array(c,"scheduled")).sortedBy{it.optLong("fireAt")}.take(20).map{mapOf("title" to it.optString("title"),"fireAt" to it.optLong("fireAt"),"kind" to if(it.has("parentKey"))"延后提醒" else if(it.optString("sourceKind")=="task")"事件关联" else if(it.optString("sourceKind")=="shift")"排班闹钟" else "独立闹钟")}
        return mapOf("exact" to exact(c),"notifications" to nm.areNotificationsEnabled(),"fullScreen" to (Build.VERSION.SDK_INT<34||nm.canUseFullScreenIntent()),"battery" to pm.isIgnoringBatteryOptimizations(c.packageName),"scheduledCount" to array(c,"scheduled").length(),"nextLabel" to label,"nativeGeneration" to state(c).optInt("nativeGeneration",0),"upcoming" to upcoming,"todoPinned" to prefs(c).getBoolean("todoPinned",false))
    }
}
class AlarmReceiver:BroadcastReceiver(){override fun onReceive(context:Context,intent:Intent){val key=intent.getStringExtra("key")?:return;val id=intent.getStringExtra("fireKey");val pending=goAsync();Thread{try{AlarmHub.fire(context,key,id)}finally{pending.finish()}}.start()}}
class RecoveryReceiver:BroadcastReceiver(){override fun onReceive(context:Context,intent:Intent){
    val pending=goAsync();Thread {try{AlarmHub.reconcile(context)}finally{pending.finish()}}.start()
}}
