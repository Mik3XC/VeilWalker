package org.trailbound.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import org.trailbound.core.data.dao.DayTotal
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.data.entity.StepInterval
import org.trailbound.core.route.RouteRepository
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class StatsViewModel @Inject constructor(steps: StepDao, routes: RouteRepository) : ViewModel() {
    val strideM: StateFlow<Double> = routes.strideM.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), RouteRepository.DEFAULT_STRIDE_M)
    val days: StateFlow<List<DayTotal>> = steps.observeDailyTotals().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val today: StateFlow<List<StepInterval>> = steps.observeIntervalsForDay(LocalDate.now().toString())
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
}

/** One labelled bucket of the chart. */
data class Bucket(val label: String, val steps: Long)

object StepChart {
    const val GOAL = 10_000L
    private const val BLOCKS = " ▁▂▃▄▅▆▇█"

    fun hourly(intervals: List<StepInterval>, zone: ZoneId = ZoneId.systemDefault()): List<Bucket> {
        val byHour = LongArray(24)
        intervals.forEach { byHour[Instant.ofEpochMilli(it.endEpochMs).atZone(zone).hour] += it.steps }
        return (0 until 24).map { Bucket("%02d".format(it), byHour[it]) }
    }

    fun lastDays(days: List<DayTotal>, n: Int, today: LocalDate = LocalDate.now()): List<Bucket> {
        val map = days.associate { it.day to it.steps }
        return (n - 1 downTo 0).map { back ->
            val d = today.minusDays(back.toLong())
            val label = if (n <= 7) d.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.US) else d.dayOfMonth.toString()
            Bucket(label, map[d.toString()] ?: 0)
        }
    }

    fun months(days: List<DayTotal>, today: LocalDate = LocalDate.now()): List<Bucket> =
        (11 downTo 0).map { back ->
            val m = today.minusMonths(back.toLong())
            val key = "%04d-%02d".format(m.year, m.monthValue)
            Bucket(m.month.getDisplayName(TextStyle.SHORT, Locale.US), days.filter { it.day.startsWith(key) }.sumOf { it.steps })
        }

    fun years(days: List<DayTotal>): List<Bucket> =
        days.groupBy { it.day.take(4) }.toSortedMap().map { (y, ds) -> Bucket(y, ds.sumOf { it.steps }) }.ifEmpty { listOf(Bucket(LocalDate.now().year.toString(), 0)) }

    /** Vertical sparkline: one block character per bucket, scaled to the busiest one. */
    fun spark(b: List<Bucket>): String {
        val max = b.maxOfOrNull { it.steps }?.coerceAtLeast(1) ?: 1
        return b.joinToString("") { BLOCKS[((it.steps * 8 + max - 1) / max).toInt().coerceIn(0, 8)].toString() }
    }

    /** Horizontal bars with a '|' marking the goal where it fits on the scale. */
    fun bars(b: List<Bucket>, width: Int = 18, goal: Long? = GOAL, strideM: Double? = null): List<String> {
        val max = maxOf(b.maxOfOrNull { it.steps } ?: 0, goal ?: 0).coerceAtLeast(1)
        val labelW = b.maxOf { it.label.length }
        return b.map { k ->
            val filled = (k.steps * width / max).toInt()
            val goalAt = goal?.let { (it * width / max).toInt().coerceIn(0, width - 1) }
            val bar = (0 until width).joinToString("") { i -> when { i < filled -> "#"; i == goalAt -> "|"; else -> "." } }
            "${k.label.padEnd(labelW)} $bar %,d".format(k.steps) + (strideM?.let { " %.1fkm".format(RouteRepository.km(k.steps, it)) } ?: "")
        }
    }
}

@Composable
fun StatsScreen(onBack: () -> Unit, vm: StatsViewModel = hiltViewModel()) {
    val days by vm.days.collectAsStateWithLifecycle()
    val today by vm.today.collectAsStateWithLifecycle()
    val stride by vm.strideM.collectAsStateWithLifecycle()
    fun km(steps: Long) = RouteRepository.km(steps, stride)
    var range by rememberSaveable { mutableStateOf("week") }
    val violet = MaterialTheme.colorScheme.primary
    val green = MaterialTheme.colorScheme.secondary
    val dim = MaterialTheme.colorScheme.onSurfaceVariant

    val buckets = when (range) {
        "day" -> StepChart.hourly(today)
        "week" -> StepChart.lastDays(days, 7)
        "month" -> StepChart.lastDays(days, 30)
        "year" -> StepChart.months(days)
        else -> StepChart.years(days)
    }
    val total = buckets.sumOf { it.steps }
    val active = days.filter { it.steps > 0 }
    val avg = if (active.isEmpty()) 0 else active.sumOf { it.steps } / active.size
    val best = days.maxByOrNull { it.steps }
    val goalDays = days.count { it.steps >= StepChart.GOAL }

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Stats", style = MaterialTheme.typography.headlineMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            listOf("day", "week", "month", "year", "all").forEach { r ->
                Text(
                    if (r == range) "[$r]" else r,
                    color = if (r == range) violet else MaterialTheme.colorScheme.outline,
                    fontWeight = if (r == range) FontWeight.Bold else FontWeight.Normal,
                    modifier = Modifier.clickable { range = r }.padding(vertical = 6.dp),
                )
            }
        }
        HorizontalDivider(thickness = 1.dp, color = violet)

        Text("%,d steps · %.1f km".format(total, km(total)), style = MaterialTheme.typography.headlineSmall, color = violet)
        if (range == "day" || range == "month") {
            // Sparkline view: one character per hour / day, labels underneath.
            Column(Modifier.horizontalScroll(rememberScrollState())) {
                Text(StepChart.spark(buckets), color = green, fontFamily = FontFamily.Monospace, fontSize = 22.sp, letterSpacing = 1.sp)
                Text(
                    buckets.mapIndexed { i, b -> if (i % (if (range == "day") 6 else 5) == 0) b.label.padEnd(if (range == "day") 6 else 5) else "" }.joinToString(""),
                    color = dim, fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                )
            }
        } else {
            StepChart.bars(buckets, goal = if (range == "week") StepChart.GOAL else null, strideM = stride).forEach {
                Text(it, color = green, fontFamily = FontFamily.Monospace, fontSize = 13.sp)
            }
            if (range == "week") Text("| = 10,000 step goal", color = dim, style = MaterialTheme.typography.bodySmall)
        }

        Text("// how you're doing", color = green, modifier = Modifier.padding(top = 8.dp))
        Text("avg day      %,d · %.1f km".format(avg, km(avg)), fontFamily = FontFamily.Monospace)
        Text("best day     %,d%s".format(best?.steps ?: 0, best?.let { " (${it.day.drop(5)})" } ?: ""), fontFamily = FontFamily.Monospace)
        Text("lifetime km  %.1f".format(km(days.sumOf { it.steps })), fontFamily = FontFamily.Monospace)
        Text("10k days     $goalDays", fontFamily = FontFamily.Monospace)
        Text("days walked  ${active.size}", fontFamily = FontFamily.Monospace)
        Text("km = your true steps x your stride (%.2f m, calibrated from your GPS walks).".format(stride), color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall)
        Text("All of this is computed on your phone.", color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall)

        VeilButton("Back", onBack, glyph = "<")
    }
}
