package cn.youqi.youqi

import org.junit.Assert.*
import org.junit.Test
import java.time.*

class RuleEngineTest {
    private val zone=ZoneId.of("Asia/Shanghai")
    private fun instant(text:String)=LocalDateTime.parse(text).atZone(zone).toInstant()
    private fun rule(type:String="daily",time:String="07:00")=AlarmRule("test",type,LocalDate.parse("2026-10-11"),LocalTime.parse(time),zone=zone)
    private fun next(r:AlarmRule,after:String)=RuleEngine.next(r,instant(after))!!.at
    @Test fun oncePastDoesNotRepeat(){assertNull(RuleEngine.next(rule("once"),instant("2026-10-11T07:01")))}
    @Test fun dailyMovesToTomorrow(){assertEquals(instant("2026-10-12T07:00"),next(rule(),"2026-10-11T07:00"))}
    @Test fun weekdaySkipsSunday(){assertEquals(instant("2026-10-12T07:00"),next(rule("weekly").copy(weekdays=(1..5).toSet()),"2026-10-11T00:00"))}
    @Test fun intervalPreservesAnchor(){assertEquals(instant("2026-10-15T07:00"),next(rule("interval").copy(intervalDays=2),"2026-10-14T00:00"))}
    @Test fun threeDayShiftRestAndMultipleTimes(){
        val r=rule("shift").copy(cycle=listOf(listOf(LocalTime.of(7,0),LocalTime.of(19,0)),listOf(LocalTime.of(6,0)),emptyList()))
        assertEquals(instant("2026-10-11T19:00"),next(r,"2026-10-11T07:01"))
        assertEquals(instant("2026-10-12T06:00"),next(r,"2026-10-11T19:01"))
        assertEquals(instant("2026-10-14T07:00"),next(r,"2026-10-12T06:01"))
    }
    @Test fun exceptionDoesNotShiftCycle(){
        val r=rule("shift").copy(cycle=listOf(listOf(LocalTime.of(7,0)),listOf(LocalTime.of(6,0)),emptyList()),exceptions=mapOf(LocalDate.parse("2026-10-12") to emptyList(),LocalDate.parse("2026-10-13") to listOf(LocalTime.of(9,0))))
        assertEquals(instant("2026-10-13T09:00"),next(r,"2026-10-11T08:00"))
        assertEquals(instant("2026-10-14T07:00"),next(r,"2026-10-13T10:00"))
    }
    @Test fun offsetBeforeMidnight(){assertEquals(instant("2026-10-11T23:40"),next(rule("once","00:10").copy(start=LocalDate.parse("2026-10-12"),offsetMinutes=-30),"2026-10-11T20:00"))}
    @Test fun overnightEndOffset(){assertEquals(instant("2026-10-12T00:30"),next(rule("once","01:00").copy(dayOffset=1,offsetMinutes=-30),"2026-10-11T20:00"))}
    @Test fun completedBaseDateExcluded(){assertEquals(instant("2026-10-12T07:00"),next(rule().copy(excluded=setOf(LocalDate.parse("2026-10-11"))),"2026-10-11T00:00"))}
    @Test fun overnightWindow(){val r=rule("window","23:00").copy(windowEnd=LocalTime.of(1,0),intervalMinutes=30);assertEquals(instant("2026-10-12T00:30"),next(r,"2026-10-12T00:10"))}
    @Test fun skippedOccurrenceOnly(){val r=rule();val first=RuleEngine.next(r,instant("2026-10-11T00:00"))!!;assertEquals(instant("2026-10-12T07:00"),RuleEngine.next(r,instant("2026-10-11T00:00"),setOf(first.fireKey))!!.at)}
    @Test fun daylightSavingGapMovesForward(){val r=rule("once","02:30").copy(start=LocalDate.parse("2026-03-08"),zone=ZoneId.of("America/New_York"));assertEquals(Instant.parse("2026-03-08T07:30:00Z"),RuleEngine.next(r,Instant.parse("2026-03-08T00:00:00Z"))!!.at)}
}
