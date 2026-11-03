package org.trailbound.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.trailbound.core.route.Journey
import kotlinx.coroutines.delay
import org.trailbound.core.route.Journeys
import org.trailbound.core.route.Rarity
import org.trailbound.core.route.Peak
import org.trailbound.core.route.Peaks
import org.trailbound.core.achievements.AchievementRules

private const val REVEAL_MS = 220L

/** A journey you can't walk yet: same frame as the live card, but everything dimmed, with a lock. */
@Composable
fun LockedJourneyCard(j: Journey, onOpen: () -> Unit = {}) {
    val muted = MaterialTheme.colorScheme.outline
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier.veilPanel(outlined = true, padding = 0.dp).veilClick(onClick = onOpen).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row {
            Text("[#] ", color = muted, fontWeight = FontWeight.Bold)
            Text(j.title.uppercase(), color = dim, fontWeight = FontWeight.Bold)
        }
        Text(j.subtitle, color = muted, style = MaterialTheme.typography.bodySmall)
        Text("[..........] ~%,d km · %d cards".format(j.km, j.postcards), color = muted, style = MaterialTheme.typography.bodySmall)
        Text(j.teaser, color = dim, style = MaterialTheme.typography.bodyMedium)
        Text(
            (if (j.unlock == "coming soon") "// coming soon" else "// unlock: ${j.unlock}") + "   > learn more",
            color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.6f),
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

/** An Outlaws on Foot collectible: evidence-card frame, rarity, the quote, and a progress bar toward its step target. */
@Composable
fun OutlawCardView(j: Journey, lifetime: Long, onOpen: () -> Unit = {}) {
    val c = j.card ?: return
    val got = lifetime >= c.steps
    val violet = MaterialTheme.colorScheme.primary
    val green = MaterialTheme.colorScheme.secondary
    val muted = MaterialTheme.colorScheme.outline
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier.veilPanel(outlined = true, outline = if (got) green else if (c.rarity == Rarity.BOSS) violet else Color.Unspecified, lineWidth = if (c.rarity >= Rarity.LEGENDARY) 2.dp else 1.dp, padding = 0.dp)
            .veilClick(onClick = onOpen).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row {
            Text(if (got) "[+] " else "[#] ", color = if (got) green else muted, fontWeight = FontWeight.Bold)
            Text(j.title.uppercase(), color = if (got) green else dim, fontWeight = FontWeight.Bold)
        }
        Text("${c.rarity.label} \u00b7 ${j.subtitle}", color = if (c.rarity >= Rarity.LEGENDARY) violet else muted, style = MaterialTheme.typography.bodySmall)
        Text("\u201c${c.quote}\u201d", color = dim, style = MaterialTheme.typography.bodyMedium)
        Text(
            asciiBar(lifetime.toDouble() / c.steps).substringBefore("]") + "] " +
                if (got) "collected" else "${AchievementRules.compact(lifetime.coerceAtMost(c.steps))} / ${AchievementRules.compact(c.steps)}",
            color = if (got) green else muted, style = MaterialTheme.typography.bodySmall,
        )
        Text("> learn more", color = green.copy(alpha = 0.6f), style = MaterialTheme.typography.bodySmall)
    }
}

/**
 * A Hidden Peaks card. Climbed peaks show in full (K2 as the Demon); the next one shows only a progress bar;
 * the rest are just "???" so there's something left to discover.
 */
@Composable
fun PeakCardView(p: Peak, climbedM: Double, isNext: Boolean, onOpen: () -> Unit = {}) {
    val got = climbedM >= p.heightM
    val ice = VeilColors.ice
    val violet = MaterialTheme.colorScheme.primary
    val muted = MaterialTheme.colorScheme.outline
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier.veilPanel(outlined = true, outline = if (got) (if (p.demon) violet else ice) else Color.Unspecified, lineWidth = if (p.demon && got) 2.dp else 1.dp, padding = 0.dp)
            .veilClick(enabled = got, onClick = onOpen).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (!got) {
            Text("[?] HIDDEN PEAK", color = muted, fontWeight = FontWeight.Bold)
            if (isNext) {
                Text(asciiBar(climbedM / p.heightM).substringBefore("]") + "] %,d m cold climb".format(climbedM.toLong()), color = muted, style = MaterialTheme.typography.bodySmall)
                Text("walk when you see the \u2744 (hills count extra)", color = dim, style = MaterialTheme.typography.bodySmall)
            } else {
                Text("??? \u00b7 ?,??? m", color = muted, style = MaterialTheme.typography.bodySmall)
            }
            return@Column
        }
        if (p.demon) AvatarArt(3, size = 10.sp)
        Row {
            Text("[^] ", color = if (p.demon) violet else ice, fontWeight = FontWeight.Bold)
            Text(p.name.uppercase(), color = if (p.demon) violet else ice, fontWeight = FontWeight.Bold)
        }
        Text("${p.region} \u00b7 %,d m / %,d ft".format(p.heightM, p.heightFt), color = dim, style = MaterialTheme.typography.bodySmall)
        Text("\u201c${p.quote}\u201d", color = dim, style = MaterialTheme.typography.bodyMedium)
        if (p.demon) Text("[)v(] THE CROWLEY AWARD", color = violet, fontWeight = FontWeight.Bold)
        Text("> learn more", color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.6f), style = MaterialTheme.typography.bodySmall)
    }
}

/** A climbed peak's story. Only reachable once it's been climbed, so the deck stays hidden. */
@Composable
fun PeakDetailScreen(id: String, onBack: () -> Unit) {
    val p = Peaks.all.firstOrNull { it.id == id } ?: return onBack()
    val violet = MaterialTheme.colorScheme.primary
    val green = MaterialTheme.colorScheme.secondary
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(if (p.demon) "[)v(] SUMMITED \u00b7 THE CROWLEY AWARD" else "[^] SUMMITED", color = if (p.demon) violet else green, fontWeight = FontWeight.Bold)
        if (p.demon) AvatarArt(3, size = 12.sp)
        Text(p.name, style = MaterialTheme.typography.headlineMedium)
        Text(p.region, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("%,d m \u00b7 %,d ft".format(p.heightM, p.heightFt), color = violet)
        Text("\u201c${p.quote}\u201d", color = violet, style = MaterialTheme.typography.titleMedium)
        Text("// timeline", color = green)
        p.facts.forEach { f -> Row { Text("\u25b8 ", color = violet); Text(f, style = MaterialTheme.typography.bodyMedium) } }
        Text("You climbed its full height on freezing walks: every cold step is 7 cm of mountain trail, and real hills, measured by your barometer, count on top.", color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall)
        VeilButton("Back", onBack, glyph = "<")
    }
}

/** Every journey: the live one first, then all the locked ones. */
@Composable
fun JourneysScreen(onBack: () -> Unit, onOpen: (String) -> Unit, onOpenPeak: (String) -> Unit = {}, vm: HomeViewModel = hiltViewModel()) {
    val route by vm.route.collectAsStateWithLifecycle()
    val lifetime by vm.lifetimeSteps.collectAsStateWithLifecycle()
    val collected = Journeys.outlaws.count { lifetime >= (it.card?.steps ?: Long.MAX_VALUE) }
    val climbed by vm.coldClimbM.collectAsStateWithLifecycle()
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Journeys", style = MaterialTheme.typography.headlineMedium)
        Text("Walk for Freedom · ${Journeys.all.size - Journeys.outlaws.size} journeys · 1 open", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("Outlaws on Foot · $collected/${Journeys.outlaws.size} cards collected", color = MaterialTheme.colorScheme.onSurfaceVariant)
        // Cards load in one at a time, like lines arriving in a terminal.
        var shown by remember { mutableIntStateOf(0) }
        LaunchedEffect(Unit) {
            while (shown < Journeys.all.size) { delay(REVEAL_MS); shown++ }
        }
        Journeys.all.forEachIndexed { i, j ->
            AnimatedVisibility(
                visible = i < shown,
                enter = fadeIn(tween(300)) + slideInVertically(tween(300)) { it / 4 },
            ) {
                val header = j.card?.collection?.takeIf { it != Journeys.all.getOrNull(i - 1)?.card?.collection }
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    header?.let { Text("// $it", color = MaterialTheme.colorScheme.secondary, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp)) }
                    when {
                        j.route != null -> Column { route?.let { RouteCard(it) }; VeilButton("Learn more: ${j.title}", { onOpen(j.id) }, glyph = ">") }
                        j.card != null -> OutlawCardView(j, lifetime) { onOpen(j.id) }
                        else -> LockedJourneyCard(j) { onOpen(j.id) }
                    }
                }
            }
        }
        if (shown < Journeys.all.size) Text("loading ${shown + 1}/${Journeys.all.size}_", color = MaterialTheme.colorScheme.secondary)
        else {
            Text("// ${Peaks.TITLE}", color = MaterialTheme.colorScheme.secondary, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
            val next = Peaks.all.firstOrNull { climbed < it.heightM }
            Peaks.all.forEach { p -> PeakCardView(p, climbed, isNext = p == next) { onOpenPeak(p.id) } }
        }
        VeilButton("Back", onBack, glyph = "<")
    }
}


/** Everything we know about one journey: the teaser, a timeline of facts, and why it's in VeilWalker. */
@Composable
fun JourneyDetailScreen(id: String, onBack: () -> Unit, vm: HomeViewModel = hiltViewModel()) {
    val j = Journeys.byId(id) ?: return onBack()
    val lifetime by vm.lifetimeSteps.collectAsStateWithLifecycle()
    val card = j.card
    val green = MaterialTheme.colorScheme.secondary
    val violet = MaterialTheme.colorScheme.primary
    val dim = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val got = card != null && lifetime >= card.steps
        Text(
            when { j.route != null -> "[>] WALKING NOW"; got -> "[+] COLLECTED"; card != null -> "[#] ${card.rarity.label} \u00b7 LOCKED"; else -> "[#] LOCKED" },
            color = if (j.route != null || got) green else MaterialTheme.colorScheme.outline, fontWeight = FontWeight.Bold,
        )
        Text(j.title, style = MaterialTheme.typography.headlineMedium)
        Text(j.subtitle, color = dim)
        if (card != null) {
            Text("\u201c${card.quote}\u201d", color = violet, style = MaterialTheme.typography.titleMedium)
            Text("%,d / %,d steps (~%,d km)".format(lifetime.coerceAtMost(card.steps), card.steps, j.km), color = violet)
            Text(card.collection, color = dim, style = MaterialTheme.typography.bodySmall)
        } else {
            Text("~%,d km \u00b7 %d postcards".format(j.km, j.postcards), color = violet)
        }
        Text(j.teaser, style = MaterialTheme.typography.bodyLarge)

        Text("// timeline", color = green)
        j.facts.forEach { f ->
            Row { Text("\u25b8 ", color = violet); Text(f, style = MaterialTheme.typography.bodyMedium) }
        }
        if (j.why.isNotEmpty()) {
            Text("// why it's here", color = green)
            Text(j.why, color = dim, style = MaterialTheme.typography.bodyMedium)
        }
        Text(
            when {
                j.route != null -> "// you're on it"
                got -> "// in your collection"
                j.unlock == "coming soon" -> "// coming soon"
                else -> "// unlock: ${j.unlock}"
            },
            color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.7f),
        )
        if (card != null) Text("History is real; the step target and rarity are game mechanics.", color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall)
        Text("Draft history, pending review. Spotted an error? premiselayer@gmail.com", color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall)
        VeilButton("Back", onBack, glyph = "<")
    }
}
