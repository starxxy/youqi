package cn.youqi.youqi

import org.junit.Assert.*
import org.junit.Test

class AlarmPolicyTest {
    @Test fun firstAlarmStartsAtOneAndSnoozesDarkenToSeven() {
        assertEquals((1..7).toList(), (0..6).map(AlarmPolicy::level))
        assertEquals(7, AlarmPolicy.level(7))
        assertEquals(7, AlarmPolicy.level(100))
        assertEquals(1, AlarmPolicy.level(-1))
        // A new independent occurrence has a new counter, regardless of yesterday.
        assertEquals(1, AlarmPolicy.level(0))
    }
    @Test fun quickSnoozesUseTheExplicitDelayAndCrossMidnight() {
        val now = java.time.Instant.parse("2026-10-12T23:58:00Z").toEpochMilli()
        assertEquals(java.time.Instant.parse("2026-10-13T00:03:00Z").toEpochMilli(), AlarmPolicy.fireAt(now,5))
        assertEquals(java.time.Instant.parse("2026-10-13T00:08:00Z").toEpochMilli(), AlarmPolicy.fireAt(now,10))
        assertEquals(5, AlarmPolicy.delayMinutes(5,30))
        assertEquals(10, AlarmPolicy.delayMinutes(10,30))
        assertEquals(30, AlarmPolicy.delayMinutes(null,30))
    }
    @Test fun manualSnoozeIsAvailableWhileAutomaticRepeatHasALimit() {
        assertTrue(AlarmPolicy.canSnooze(true,3,3))
        assertTrue(AlarmPolicy.canSnooze(true,10,0))
        assertFalse(AlarmPolicy.canSnooze(false,3,3))
        assertTrue(AlarmPolicy.canSnooze(false,2,3))
    }
    @Test fun staleOrMissingActionsNeverAffectTheNextQueuedAlarm() {
        assertTrue(AlarmPolicy.acceptsAction("rule@1","rule@1"))
        assertFalse(AlarmPolicy.acceptsAction("rule@1","rule@2"))
        assertFalse(AlarmPolicy.acceptsAction(null,"rule@1"))
    }
}
