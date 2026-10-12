package cn.youqi.youqi

/** Independent of Android so retry boundaries and stale actions can be tested. */
object AlarmPolicy {
    fun level(snoozeCount: Int) = snoozeCount.coerceIn(0, 6) + 1
    fun acceptsAction(expected: String?, active: String) = expected != null && expected == active
    fun delayMinutes(explicit: Int?, configured: Int) = (explicit ?: configured).coerceIn(1, 1440)
    fun canSnooze(manual: Boolean, attempt: Int, maximum: Int) = manual || attempt < maximum.coerceAtLeast(0)
    fun fireAt(now: Long, minutes: Int) = now + minutes.coerceIn(1, 1440) * 60_000L
}
