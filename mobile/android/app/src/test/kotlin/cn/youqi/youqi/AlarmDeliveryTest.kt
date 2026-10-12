package cn.youqi.youqi

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.app.Notification
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.Robolectric
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28, 35])
class AlarmDeliveryTest {
    private lateinit var context: Context
    private lateinit var manager: AlarmManager
    private val now = Instant.parse("2026-10-12T08:00:00Z")
    private fun at(time: Instant) { AlarmHub.clock = Clock.fixed(time,ZoneOffset.UTC) }
    private fun records(key: String = "scheduled") = AlarmHub.jsonList(JSONArray(AlarmHub.prefs(context).getString(key,"[]")!!))
    private fun seed(type: String = "once", key: String = "task:demo:start") {
        val rule=JSONObject().put("key",key).put("type",type).put("title","关联事件")
            .put("startDate","2026-10-12").put("time","08:31").put("offset",-30)
            .put("fixedZone",true).put("timeZone","UTC").put("enabled",true)
        AlarmHub.prefs(context).edit().putString("state",JSONObject().put("deviceMode","ring")
            .put("nativeRules",JSONArray().put(rule)).toString()).commit()
    }
    @Before fun setup() {
        context=RuntimeEnvironment.getApplication()
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(android.Manifest.permission.POST_NOTIFICATIONS)
        manager=context.getSystemService(AlarmManager::class.java)
        org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(true)
        AlarmHub.prefs(context).edit().clear().commit()
        at(now)
    }
    @After fun cleanup() { AlarmHub.clock=Clock.systemDefaultZone() }
    @Test fun eventIsNotDeletedWhenRefreshWinsTheRaceWithBroadcast() {
        seed(); AlarmHub.reconcile(context)
        val original=records().single()
        at(Instant.ofEpochMilli(original.getLong("fireAt")).plusMillis(1))
        AlarmHub.reconcile(context)
        assertTrue("到期但广播尚未处理的事件必须保留",records().any {it.getString("fireKey")==original.getString("fireKey")})
    }
    @Test fun fiveMinuteSnoozeSurvivesRefreshAtItsDeadline() {
        seed(); AlarmHub.reconcile(context)
        val original=records().single()
        assertTrue(AlarmHub.snooze(context,original,5))
        val snooze=records().single { it.has("parentKey") }
        assertEquals(now.plusSeconds(300).toEpochMilli(),snooze.getLong("fireAt"))
        at(now.plusSeconds(300).plusMillis(1)); AlarmHub.reconcile(context)
        assertTrue("5分钟到时不能先删延后记录",records().any {it.getString("fireKey")==snooze.getString("fireKey")})
    }
    @Test fun reopeningRepairsSystemAlarmsEvenWhenLocalRecordsAreUnchanged() {
        seed(); AlarmHub.reconcile(context)
        val alarm=shadowOf(manager).scheduledAlarms.single()
        manager.cancel(alarm.operation!!)
        assertTrue(shadowOf(manager).scheduledAlarms.isEmpty())
        AlarmHub.reconcile(context)
        assertEquals("本地有记录不等于系统已登记",1,shadowOf(manager).scheduledAlarms.size)
    }
    private fun dispatch(record:JSONObject) {
        val alarm=shadowOf(manager).scheduledAlarms.first { shadowOf(it.operation!!).savedIntent.getStringExtra("fireKey")==record.getString("fireKey") }
        val intent=shadowOf(alarm.operation!!).savedIntent
        AlarmHub.fire(context,intent.getStringExtra("key")!!,intent.getStringExtra("fireKey"))
    }
    private fun started():JSONObject = JSONObject(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService!!.getStringExtra("payload")!!)
    @Test fun dailyDueRecordDispatchesEvenAfterNextDayIsRegistered() {
        seed("daily");AlarmHub.reconcile(context);val due=records().single()
        at(Instant.ofEpochMilli(due.getLong("fireAt")).plusSeconds(1));AlarmHub.reconcile(context)
        assertEquals(2,records().size)
        dispatch(due);assertEquals(due.getString("fireKey"),started().getString("fireKey"))
        assertEquals(1,records().size)
        assertTrue(records().single().getLong("fireAt")>AlarmHub.clock.millis())
        AlarmHub.fire(context,due.getString("key"),due.getString("fireKey"))
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }
    @Test fun snoozeButtonsRearmAndDeliverFiveThenTenMinutesWithDarkerLevel() {
        seed();AlarmHub.reconcile(context);var record=records().single()
        at(Instant.ofEpochMilli(record.getLong("fireAt")));dispatch(record);record=started()
        val controller=Robolectric.buildService(AlarmService::class.java).create()
        try {
            val service=controller.get()
            service.onStartCommand(Intent("ring").putExtra("payload",record.toString()),0,1)
            assertNotNull(service.active)
            service.onStartCommand(Intent("snooze5").putExtra("fireKey",record.getString("fireKey")),0,2)
            assertNull(service.active)
            var next=records().single {it.has("parentKey")}
            assertEquals(AlarmHub.clock.millis()+300_000,next.getLong("fireAt"))
            at(Instant.ofEpochMilli(next.getLong("fireAt")).plusMillis(1));AlarmHub.reconcile(context)
            dispatch(next);record=started()
            assertEquals(1,record.getInt("snoozeCount"));assertEquals(2,AlarmPolicy.level(record.getInt("snoozeCount")))
            service.onStartCommand(Intent("ring").putExtra("payload",record.toString()),0,3)
            // An old notification action must not stop the currently ringing delivery.
            service.onStartCommand(Intent("snooze10").putExtra("fireKey","old"),0,4)
            assertNotNull(service.active)
            service.onStartCommand(Intent("snooze10").putExtra("fireKey",record.getString("fireKey")),0,5)
            assertNull(service.active)
            next=records().single {it.has("parentKey")}
            assertEquals(AlarmHub.clock.millis()+600_000,next.getLong("fireAt"))
            at(Instant.ofEpochMilli(next.getLong("fireAt")).plusMillis(1));AlarmHub.reconcile(context)
            dispatch(next);assertEquals(2,started().getInt("snoozeCount"))
        } finally {controller.destroy()}
    }
    @Test fun simultaneousStartAndEndRemindersAreBothDelivered() {
        seed();val root=AlarmHub.state(context);val rules=root.getJSONArray("nativeRules")
        rules.put(JSONObject(rules.getJSONObject(0).toString()).put("key","task:demo:end"))
        AlarmHub.prefs(context).edit().putString("state",root.toString()).commit();AlarmHub.reconcile(context)
        val due=records();at(Instant.ofEpochMilli(due.first().getLong("fireAt")))
        dispatch(due[0]);assertEquals(due[0].getString("fireKey"),started().getString("fireKey"))
        dispatch(due[1]);assertEquals(due[1].getString("fireKey"),started().getString("fireKey"))
        assertTrue(records().isEmpty())
    }
    @Test fun editingDisablingAndCancellingDoNotResurrectOldDeliveries() {
        seed();AlarmHub.reconcile(context);val original=records().single()
        assertTrue(AlarmHub.snooze(context,original,5))
        val root=AlarmHub.state(context);root.getJSONArray("nativeRules").getJSONObject(0).put("time","09:00")
        AlarmHub.prefs(context).edit().putString("state",root.toString()).commit();AlarmHub.reconcile(context)
        assertFalse(records().any{it.has("parentKey")})
        at(Instant.ofEpochMilli(original.getLong("fireAt")));AlarmHub.fire(context,original.getString("key"),original.getString("fireKey"))
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        AlarmHub.oneShot(context,JSONObject().put("key","test:cancel"));AlarmHub.cancelShot(context,"test:cancel")
        assertFalse(records().any{it.optString("key")=="test:cancel"})
        AlarmHub.disable(context,records().single());assertTrue(records().isEmpty())
    }
    @Test fun completedOccurrenceCancelsEventAndItsSnooze() {
        seed();val root=AlarmHub.state(context)
        root.getJSONArray("nativeRules").getJSONObject(0).put("occurrenceId","demo@2026-10-12")
        root.put("tasks",JSONArray().put(JSONObject().put("id","demo")))
        root.put("occurrences",JSONObject().put("demo@2026-10-12",JSONObject().put("taskId","demo").put("done",false)))
        AlarmHub.prefs(context).edit().putString("state",root.toString()).commit();AlarmHub.reconcile(context)
        assertTrue(AlarmHub.snooze(context,records().single(),5))
        root.getJSONObject("occurrences").getJSONObject("demo@2026-10-12").put("done",true)
        AlarmHub.prefs(context).edit().putString("state",root.toString()).commit();AlarmHub.reconcile(context)
        assertTrue(records().isEmpty())
    }
    @Test fun repeatedReconcileKeepsOnlyOneSystemTimerPerDelivery() {
        seed("daily");repeat(5){AlarmHub.reconcile(context)}
        assertEquals(1,records().size);assertEquals(1,shadowOf(manager).scheduledAlarms.size)
    }
    @Test fun allRuleFamiliesRegisterAndDispatchTheirOwnPayloads() {
        val rules=JSONArray()
        for(type in listOf("once","daily","weekly","interval","window","shift")) {
            rules.put(JSONObject().put("key","family:$type").put("title",type).put("type",type)
                .put("startDate","2026-10-12").put("time","08:31").put("offset",-30)
                .put("weekdays",JSONArray(listOf(1,2,3,4,5))).put("interval",3)
                .put("windowEnd","10:00").put("intervalMinutes",30)
                .put("days",JSONArray().put(JSONObject().put("times",JSONArray(listOf("08:31")))).put(JSONObject().put("times",JSONArray(listOf("07:00")))).put(JSONObject().put("times",JSONArray())))
                .put("fixedZone",true).put("timeZone","UTC"))
        }
        AlarmHub.prefs(context).edit().putString("state",JSONObject().put("nativeRules",rules).toString()).commit()
        AlarmHub.reconcile(context);val first=records()
        assertEquals(6,first.size);assertTrue(first.all{it.getLong("fireAt")==now.plusSeconds(60).toEpochMilli()})
        at(now.plusSeconds(60).plusMillis(1));AlarmHub.reconcile(context)
        for(record in first){dispatch(record);assertEquals(record.getString("fireKey"),started().getString("fireKey"))}
        assertEquals(5,records().size)
    }
    @Test fun failedServiceStartRetainsDeliveryAndRetriesWithoutConsumingIt() {
        seed();AlarmHub.reconcile(context);val original=records().single()
        at(Instant.ofEpochMilli(original.getLong("fireAt")))
        val refusing=object:android.content.ContextWrapper(context){override fun startForegroundService(intent:Intent):android.content.ComponentName? {throw IllegalStateException("simulated rejection")}}
        AlarmHub.fire(refusing,original.getString("key"),original.getString("fireKey"))
        assertEquals("[]",AlarmHub.prefs(context).getString("fired","[]"))
        val retry=records().single();assertEquals(AlarmHub.clock.millis()+60_000,retry.getLong("retryAt"))
        at(Instant.ofEpochMilli(retry.getLong("retryAt")));dispatch(retry)
        assertEquals(original.getString("fireKey"),started().getString("fireKey"))
        assertTrue(records().isEmpty())
    }
    @Test fun midnightSummaryIncludesUnmaterializedRepeatsButExcludesFutureAndDeleted() {
        val task=JSONObject().put("id","daily").put("title","每日练习").put("repeat","daily")
            .put("startDate","2026-10-11").put("generatedThrough","2026-10-12")
        val root=JSONObject().put("tasks",JSONArray().put(task)).put("occurrences",JSONObject()
            .put("daily@2026-10-11",JSONObject().put("taskId","daily").put("date","2026-10-11").put("done",true))
            .put("daily@2026-10-12",JSONObject().put("taskId","daily").put("date","2026-10-12").put("done",false))
            .put("daily@2026-10-14",JSONObject().put("taskId","daily").put("date","2026-10-14").put("done",false)))
        val list=TodoNotification.items(root,java.time.LocalDate.parse("2026-10-13"))
        assertEquals(listOf("daily@2026-10-12","daily@2026-10-13"),list.map{it.id})
        task.put("deletedAt","2026-10-13T00:00:00Z")
        assertTrue(TodoNotification.items(root,java.time.LocalDate.parse("2026-10-13")).isEmpty())
    }
    @Test fun editingPersistentTaskStartDoesNotCreateExtraNotificationItem() {
        val root=JSONObject().put("tasks",JSONArray().put(JSONObject().put("id","todo").put("title","作业").put("repeat","none").put("startDate","2026-10-12")))
            .put("occurrences",JSONObject().put("todo@2026-10-11",JSONObject().put("taskId","todo").put("date","2026-10-11").put("done",false)))
        assertEquals(listOf("todo@2026-10-11"),TodoNotification.items(root,java.time.LocalDate.parse("2026-10-12")).map{it.id})
    }
    @Test fun persistentTodoIsSilentUpdatesOnCompletionAndCanBeDisabled() {
        val root=JSONObject().put("tasks",JSONArray().put(JSONObject().put("id","todo").put("title","写作业").put("startDate","2026-10-11").put("repeat","none")))
            .put("occurrences",JSONObject().put("todo@2026-10-11",JSONObject().put("taskId","todo").put("date","2026-10-11").put("done",false)))
        AlarmHub.prefs(context).edit().putString("state",root.toString()).commit()
        val nm=context.getSystemService(NotificationManager::class.java)
        assertNull(shadowOf(nm).getNotification(TodoNotification.ID))
        TodoNotification.setEnabled(context,true)
        var notification=shadowOf(nm).getNotification(TodoNotification.ID)
        assertEquals("今日待办 · 1 项未完成",notification.extras.getString(Notification.EXTRA_TITLE))
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT!=0)
        assertNull(nm.getNotificationChannel("youqi_today_v1").sound)
        root.getJSONObject("occurrences").getJSONObject("todo@2026-10-11").put("done",true)
        AlarmHub.prefs(context).edit().putString("state",root.toString()).commit();AlarmHub.reconcile(context)
        notification=shadowOf(nm).getNotification(TodoNotification.ID)
        assertEquals("今日待办 · 0 项未完成",notification.extras.getString(Notification.EXTRA_TITLE))
        TodoNotification.setEnabled(context,false)
        assertNull(shadowOf(nm).getNotification(TodoNotification.ID))
    }
}
