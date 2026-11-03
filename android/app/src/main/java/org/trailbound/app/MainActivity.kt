package org.trailbound.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import dagger.hilt.android.AndroidEntryPoint
import org.trailbound.app.ui.AboutScreen
import org.trailbound.app.ui.AccountScreen
import org.trailbound.app.ui.BadgesScreen
import org.trailbound.app.ui.BragScreen
import org.trailbound.app.ui.PeakDetailScreen
import org.trailbound.app.ui.Consent
import org.trailbound.app.ui.ConsentScreen
import org.trailbound.app.ui.HomeScreen
import org.trailbound.app.ui.CreditsScreen
import org.trailbound.app.ui.JourneyDetailScreen
import org.trailbound.app.ui.JourneysScreen
import org.trailbound.app.ui.StatsScreen
import org.trailbound.app.ui.SocialScreen
import org.trailbound.app.ui.SnowflakeScreen
import org.trailbound.app.ui.WakeScreen
import org.trailbound.app.ui.ForceDark
import org.trailbound.app.ui.VeilWalkerTheme

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            VeilWalkerTheme {
                // A handful of screens doesn't justify a navigation library yet.
                var screen by rememberSaveable { mutableStateOf(if (Consent.given(this@MainActivity)) "home" else "consent") }
                val home = { screen = "home" }
                when (screen) {
                    "consent" -> ConsentScreen(onAccept = {
                        Consent.record(this@MainActivity)
                        (application as VeilWalkerApp).startBackgroundWork()
                        screen = "home"
                    })
                    "account" -> { BackHandler(onBack = home); AccountScreen(onBack = home) }
                    "badges" -> { BackHandler(onBack = home); BadgesScreen(onBack = home) }
                    "journeys" -> { BackHandler(onBack = home); JourneysScreen(onBack = home, onOpen = { screen = "journey:$it" }, onOpenPeak = { screen = "peak:$it" }) }
                    "about" -> { BackHandler(onBack = home); AboutScreen(onBack = home, onCredits = { screen = "credits" }) }
                    "social" -> { BackHandler(onBack = home); SocialScreen(onBack = home) }
                    "stats" -> { BackHandler(onBack = home); StatsScreen(onBack = home) }
                    "brag" -> { BackHandler(onBack = home); BragScreen(onBack = home) }
                    "credits" -> { BackHandler(onBack = home); ForceDark { CreditsScreen(onBack = home) } }
                    "snowflake" -> { BackHandler(onBack = home); SnowflakeScreen(onBack = home) }
                    "wake" -> ForceDark { WakeScreen(onExit = home) }   // consumes back itself: exit is a 1 s hold
                    else -> if (screen.startsWith("peak:")) {
                        val back = { screen = "journeys" }
                        BackHandler(onBack = back); PeakDetailScreen(screen.removePrefix("peak:"), onBack = back)
                    } else if (screen.startsWith("journey:")) {
                        val back = { screen = "journeys" }
                        BackHandler(onBack = back); JourneyDetailScreen(screen.removePrefix("journey:"), onBack = back)
                    } else HomeScreen(
                        onOpenAccount = { screen = "account" },
                        onOpenBadges = { screen = "badges" },
                        onOpenJourneys = { screen = "journeys" },
                        onOpenAbout = { screen = "about" },
                        onOpenSocial = { screen = "social" },
                        onOpenStats = { screen = "stats" },
                        onOpenBrag = { screen = "brag" },
                        onOpenCredits = { screen = "credits" },
                        onOpenSnowflake = { screen = "snowflake" },
                        onOpenWake = { screen = "wake" },
                    )
                }
            }
        }
    }
}
