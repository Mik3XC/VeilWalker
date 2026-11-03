package org.trailbound.core.achievements

import org.json.JSONObject

/** One badge, expanded from a family tier. [id] is stable (family_threshold) and is what gets stored and synced. */
data class Achievement(
    val id: String,
    val family: String,
    val name: String,
    val glyph: String,
    val metric: String,
    val threshold: Long,
    val description: String,
    val secret: Boolean,
)

/**
 * Rules live in assets/achievements.json as families of tiers, so adding badges is a content edit:
 * {"id","glyph","metric","tiers":[...],"names":[...],"desc":"... {n} ...","secret"?,"format"?}.
 */
object AchievementRules {

    fun parse(json: String): List<Achievement> {
        val families = JSONObject(json).getJSONArray("families")
        return (0 until families.length()).flatMap { i ->
            val f = families.getJSONObject(i)
            val tiers = f.getJSONArray("tiers")
            val names = f.optJSONArray("names")
            val raw = f.optString("format") == "raw"
            (0 until tiers.length()).map { t ->
                val n = tiers.getLong(t)
                Achievement(
                    id = "${f.getString("id")}_$n",
                    family = f.getString("id"),
                    name = names?.optString(t)?.takeIf { it.isNotEmpty() } ?: "${f.getString("id")} $n",
                    glyph = f.getString("glyph"),
                    metric = f.getString("metric"),
                    threshold = n,
                    description = f.getString("desc").replace("{n}", if (raw) "%,d".format(n) else compact(n)),
                    secret = f.optBoolean("secret", false),
                )
            }
        }
    }

    /** 1,000 → 1K, 2,500,000 → 2.5M; small numbers stay as they are. */
    fun compact(n: Long): String = when {
        n >= 1_000_000 -> trim(n / 1_000_000.0) + "M"
        n >= 10_000 -> trim(n / 1_000.0) + "K"
        else -> "%,d".format(n)
    }

    private fun trim(v: Double) = if (v % 1.0 == 0.0) v.toLong().toString() else "%.1f".format(v)

    /** Every achievement whose metric has reached its threshold. Unknown metrics never unlock anything. */
    fun unlocked(all: List<Achievement>, metrics: Map<String, Long>): List<Achievement> =
        all.filter { (metrics[it.metric] ?: 0) >= it.threshold }
}

/**
 * Snowflake status: minutes spent hosting a Snowflake proxy while walking add frost to every badge frame.
 * Status only, never points (Play proxyware policy), and it can't be bought.
 */
enum class Frost(val title: String, val minMinutes: Long, private val left: String, private val right: String) {
    NONE("NONE", 0, "", ""),
    FROST("FROST", 10, "*", ""),
    ICE("ICE", 100, "*", "*"),
    GLACIER("GLACIER", 1000, "**", "*"),
    AURORA("AURORA", 5000, "**", "**");

    fun apply(frame: String): String = left + frame + right

    companion object {
        fun of(snowflakeMinutes: Long): Frost = entries.last { snowflakeMinutes >= it.minMinutes }
    }
}

/** Rank from how many badges are unlocked: the frame every badge is shown in. */
enum class Rank(val title: String, val minBadges: Int) {
    NONE("UNRANKED", 0), BRONZE("BRONZE", 5), SILVER("SILVER", 15), GOLD("GOLD", 30), PLATINUM("PLATINUM", 50);

    companion object {
        fun of(unlockedCount: Int): Rank = entries.last { unlockedCount >= it.minBadges }
    }
}
