package org.trailbound.app.ui

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

/** The four ASCII profile pictures. Plain ASCII only, all exactly 5 lines x 9 columns so they line up. */
data class Avatar(val name: String, val art: String)

val Avatars = listOf(
    Avatar(
        "GHOST",
        """
        |  .---.
        | ( o o )
        | |  O  |
        | |     |
        | '^^^^^'
        """.trimMargin(),
    ),
    Avatar(
        "ABYSS",
        """
        |  _/^\_  
        | / .-. \ 
        || ( * ) |
        | \ '-' / 
        | /|||||\ 
        """.trimMargin(),
    ),
    Avatar(
        "CAT",
        """
        |  /\_/\
        | ( o.o )
        |  > ^ <
        | /     \
        |(_)---(_)
        """.trimMargin(),
    ),
    Avatar(
        "DEMON",
        """
        | /)   (\ 
        |( \___/ )
        | \ >v< / 
        |  )   (  
        | / | | \ 
        """.trimMargin(),
    ),
)

/** Which avatar the user picked. Stays on the phone for now (nothing public needs it until squads). */
@Singleton
class ProfileStore @Inject constructor(@ApplicationContext context: Context) {
    private val prefs = context.getSharedPreferences("profile", Context.MODE_PRIVATE)
    private val _avatar = MutableStateFlow(prefs.getInt(KEY, 0).coerceIn(Avatars.indices))
    val avatar: StateFlow<Int> = _avatar

    fun setAvatar(index: Int) {
        prefs.edit().putInt(KEY, index).apply()
        _avatar.value = index
    }

    private companion object { const val KEY = "avatar" }
}
