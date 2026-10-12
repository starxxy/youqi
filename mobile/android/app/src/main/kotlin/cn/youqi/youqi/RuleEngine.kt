package cn.youqi.youqi

import java.time.*
import java.time.temporal.ChronoUnit
import kotlin.math.abs

data class AlarmRule(
    val key: String,
    val type: String,
    val start: LocalDate,
    val time: LocalTime = LocalTime.of(7, 0),
    val weekdays: Set<Int> = (1..7).toSet(),
    val intervalDays: Int = 1,
    val windowEnd: LocalTime = LocalTime.of(18, 0),
    val intervalMinutes: Int = 60,
    val offsetMinutes: Int = 0,
    val dayOffset: Int = 0,
    val excluded: Set<LocalDate> = emptySet(),
    val cycle: List<List<LocalTime>> = emptyList(),
    val exceptions: Map<LocalDate, List<LocalTime>> = emptyMap(),
    val zone: ZoneId = ZoneId.systemDefault()
)
data class NextFire(val key: String, val at: Instant, val baseDate: LocalDate) {
    val fireKey: String get() = "$key@${at.toEpochMilli()}"
}
object RuleEngine {
    fun next(rule: AlarmRule, after: Instant, skipped: Set<String> = emptySet()): NextFire? {
        require(rule.intervalDays in 1..365 && rule.intervalMinutes in 1..1440)
        val localNow = after.atZone(rule.zone).toLocalDate()
        val lookBehind = (abs(rule.offsetMinutes) / 1440 + abs(rule.dayOffset) + 2).toLong()
        var date = if (rule.type == "once") rule.start else maxOf(rule.start, localNow.minusDays(lookBehind))
        // All supported repeating periods are <=365 days; shift cycles <=31 days.
        val end = if (rule.type == "once") date else maxOf(date, localNow).plusDays(400 + lookBehind)
        while (!date.isAfter(end)) {
            val distance = ChronoUnit.DAYS.between(rule.start, date)
            val eligible = date !in rule.excluded && distance >= 0 && when (rule.type) {
                "once" -> date == rule.start
                "weekly", "window" -> date.dayOfWeek.value in rule.weekdays
                "interval" -> distance % rule.intervalDays == 0L
                "shift" -> rule.cycle.isNotEmpty()
                else -> true
            }
            if (eligible) {
                val localTimes = when (rule.type) {
                    "shift" -> rule.exceptions[date] ?: rule.cycle[(distance % rule.cycle.size).toInt()]
                    else -> listOf(rule.time)
                }
                for (time in localTimes.sorted()) {
                    var candidate = date.plusDays(rule.dayOffset.toLong()).atTime(time).atZone(rule.zone)
                        .plusMinutes(rule.offsetMinutes.toLong())
                    if (rule.type == "window") {
                        val until = date.plusDays(if (rule.windowEnd <= rule.time) 1 else 0)
                            .atTime(rule.windowEnd).atZone(rule.zone)
                        while (!candidate.isAfter(until)) {
                            val fire = NextFire(rule.key, candidate.toInstant(), date)
                            if (fire.at.isAfter(after) && fire.fireKey !in skipped) return fire
                            candidate = candidate.plusMinutes(rule.intervalMinutes.toLong())
                        }
                    } else {
                        val fire = NextFire(rule.key, candidate.toInstant(), date)
                        if (fire.at.isAfter(after) && fire.fireKey !in skipped) return fire
                    }
                }
            }
            date = date.plusDays(1)
        }
        return null
    }
}
