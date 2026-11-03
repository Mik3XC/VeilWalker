package org.trailbound.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import org.trailbound.core.achievements.AchievementRepository
import org.trailbound.core.achievements.AchievementRules
import org.trailbound.core.achievements.BadgeBoard
import org.trailbound.core.achievements.Frost
import org.trailbound.core.achievements.Rank
import javax.inject.Inject

@HiltViewModel
class BadgesViewModel @Inject constructor(repo: AchievementRepository) : ViewModel() {
    val board: StateFlow<BadgeBoard?> = repo.board.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
}

/** Rank frame drawn around every badge glyph: the more you've unlocked, the heavier the brackets. */
private fun frame(rank: Rank, glyph: String): String = when (rank) {
    Rank.NONE -> " $glyph "
    Rank.BRONZE -> "($glyph)"
    Rank.SILVER -> "[$glyph]"
    Rank.GOLD -> "{$glyph}"
    Rank.PLATINUM -> "<<$glyph>>"
}

@Composable
fun BadgesScreen(onBack: () -> Unit, vm: BadgesViewModel = hiltViewModel()) {
    val board by vm.board.collectAsStateWithLifecycle()
    val violet = MaterialTheme.colorScheme.primary
    val green = MaterialTheme.colorScheme.secondary
    val muted = MaterialTheme.colorScheme.outline
    val dim = MaterialTheme.colorScheme.onSurfaceVariant

    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text("Badges", style = MaterialTheme.typography.headlineMedium)
        val b = board ?: return@Column
        val next = Rank.entries.firstOrNull { it.minBadges > b.unlockedCount }
        Text("rank: ${b.rank.title}", color = green, fontWeight = FontWeight.Bold)
        Text(asciiBar(b.unlockedCount.toDouble() / b.all.size).substringBefore("]") + "]  ${b.unlockedCount}/${b.all.size}", color = violet)
        next?.let { Text("${it.minBadges - b.unlockedCount} more for ${it.title}", color = dim) }
        Text("outlaw rank: ${b.outlawRank}", color = green, fontWeight = FontWeight.Bold)
        Text(
            b.nextOutlaw?.let { "walk ${AchievementRules.compact(it.threshold)} lifetime steps to make ${it.name.uppercase()}" } ?: "KINGPIN. the whole smuggler army answers to you",
            color = dim, style = MaterialTheme.typography.bodySmall,
        )
        val nextFrost = Frost.entries.firstOrNull { it.minMinutes > b.snowflakeMinutes }
        Text(
            "frost: ${b.frost.title}" + if (b.frost == Frost.NONE) "" else " \u00b7 ${b.snowflakeMinutes} min hosted",
            color = if (b.frost == Frost.NONE) muted else green,
            fontWeight = FontWeight.Bold,
        )
        Text(
            nextFrost?.let { "host Snowflake on walks: ${it.minMinutes - b.snowflakeMinutes} more min for ${it.title}, frosts every badge" }
                ?: "max frost. every badge is aurora",
            color = dim,
            style = MaterialTheme.typography.bodySmall,
        )

        b.all.groupBy { it.family }.values.forEach { family ->
            Text("")   // spacer line, terminal style
            family.forEach { a ->
                val got = a.id in b.unlockedAt
                val hidden = a.secret && !got
                Row {
                    Text(
                        if (got) b.frost.apply(frame(b.rank, a.glyph)) else " ${a.glyph} ",
                        color = if (got) violet else muted,
                        modifier = Modifier.width(104.dp),
                    )
                    Column(Modifier.fillMaxWidth()) {
                        Text(
                            (if (got) "[x] " else "[ ] ") + (if (hidden) "?????" else a.name.uppercase()),
                            color = if (got) violet else dim,
                            fontWeight = if (got) FontWeight.Bold else FontWeight.Normal,
                        )
                        Text(
                            if (hidden) "secret" else a.description,
                            color = if (got) dim else muted,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }
        Text("")
        VeilButton("Back", onBack, glyph = "<")
    }
}
