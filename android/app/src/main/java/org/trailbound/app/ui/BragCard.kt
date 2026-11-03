package org.trailbound.app.ui

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.graphics.drawable.toBitmap
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.trailbound.app.R
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The brag engine: a 1080x1350 (4:5) JPG of avatar, handle and today's steps, the shape X, Instagram,
 * Facebook, Bluesky and Threads all accept. Drawn with a plain Canvas, so the file carries no EXIF,
 * no location and nothing about where you walked.
 */
object BragCard {
    const val W = 1080
    const val H = 1350
    private const val BG = 0xFF07070A.toInt()
    private const val VIOLET = 0xFF9D8CFF.toInt()
    private const val GREEN = 0xFF3DDC97.toInt()
    private const val TEXT = 0xFFD8D6E0.toInt()
    private const val DIM = 0xFF9A98A6.toInt()
    private const val RULE = 0xFF34333F.toInt()
    const val GOAL = 10_000L

    fun render(context: Context, avatar: Int, handle: String?, clan: String?, rank: String, today: Long, km: Double, lifetime: Long, date: LocalDate = LocalDate.now()): Bitmap {
        val bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(BG)
        val mono = Typeface.MONOSPACE
        val bold = Typeface.create(mono, Typeface.BOLD)
        fun paint(color: Int, size: Float, face: Typeface = mono, align: Paint.Align = Paint.Align.LEFT) =
            Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; textSize = size; typeface = face; textAlign = align }
        val cx = W / 2f

        // Header: logo + name, violet rule underneath (same as the home screen).
        ContextCompat.getDrawable(context, R.drawable.ic_logo)?.toBitmap(96, 96)?.let { c.drawBitmap(it, 80f, 70f, null) }
        c.drawText("VeilWalker", 200f, 140f, paint(TEXT, 60f, bold))
        c.drawRect(80f, 200f, W - 80f, 204f, Paint().apply { color = VIOLET })

        // ASCII avatar, centred.
        val art = Avatars[avatar.coerceIn(Avatars.indices)].art.lines()
        val artPaint = paint(VIOLET, 54f, bold, Paint.Align.LEFT)
        val artW = art.maxOf { artPaint.measureText(it) }
        art.forEachIndexed { i, line -> c.drawText(line, cx - artW / 2, 320f + i * 66f, artPaint) }

        val name = (clan?.let { "[$it] " } ?: "") + (handle ?: "anon")
        c.drawText(name, cx, 712f, paint(TEXT, 58f, bold, Paint.Align.CENTER))
        c.drawText("// $rank", cx, 762f, paint(GREEN, 34f, align = Paint.Align.CENTER))

        // The number.
        c.drawText("%,d".format(today), cx, 900f, paint(VIOLET, 170f, bold, Paint.Align.CENTER))
        c.drawText("steps today · %.1f km".format(km), cx, 970f, paint(DIM, 44f, align = Paint.Align.CENTER))

        // ASCII progress bar toward 10k.
        val cells = 20
        val filled = (today * cells / GOAL).toInt().coerceIn(0, cells)
        val bar = "[" + "#".repeat(filled) + ".".repeat(cells - filled) + "]"
        c.drawText(bar, cx, 1060f, paint(GREEN, 50f, bold, Paint.Align.CENTER))
        val pct = if (today >= GOAL) "10k goal smashed" else "${today * 100 / GOAL}% of 10k"
        c.drawText(pct, cx, 1115f, paint(GREEN, 36f, align = Paint.Align.CENTER))

        // Footer.
        c.drawRect(80f, 1170f, W - 80f, 1172f, Paint().apply { color = RULE })
        c.drawText("lifetime %,d".format(lifetime), 80f, 1230f, paint(TEXT, 36f))
        c.drawText(date.format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)), W - 80f, 1230f, paint(DIM, 36f, align = Paint.Align.RIGHT))
        c.drawText("walk the world. leave no trace.", cx, 1295f, paint(VIOLET, 34f, align = Paint.Align.CENTER))
        return bmp
    }

    private fun fileName(date: LocalDate) = "veilwalker-$date.jpg"

    /** Writes the JPG to app cache and opens the share sheet (X, Instagram, Facebook, Bluesky, Threads...). */
    fun share(context: Context, bmp: Bitmap, date: LocalDate = LocalDate.now()) {
        val dir = File(context.cacheDir, "brag").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
        val file = File(dir, fileName(date))
        file.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.brag", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/jpeg"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, "Brag").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Saves to Pictures/VeilWalker (Android 10+ needs no storage permission for this). */
    fun saveToGallery(context: Context, bmp: Bitmap, date: LocalDate = LocalDate.now()): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName(date))
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/VeilWalker")
        }
        val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
        return context.contentResolver.openOutputStream(uri)?.use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) } ?: false
    }
}

@Composable
fun BragScreen(onBack: () -> Unit, vm: HomeViewModel = hiltViewModel()) {
    val context = LocalContext.current
    val today by vm.todaySteps.collectAsStateWithLifecycle()
    val lifetime by vm.lifetimeSteps.collectAsStateWithLifecycle()
    val km by vm.todayKm.collectAsStateWithLifecycle()
    val rank by vm.outlawRank.collectAsStateWithLifecycle()
    val handle by vm.handle.collectAsStateWithLifecycle()
    val clan by vm.clan.collectAsStateWithLifecycle()
    val avatar by vm.avatar.collectAsStateWithLifecycle()
    val card = remember(today, km, lifetime, handle, clan, avatar, rank) { BragCard.render(context, avatar, handle, clan, rank, today, km, lifetime) }
    var note by remember { mutableStateOf<String?>(null) }

    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Brag", style = MaterialTheme.typography.headlineMedium)
        Image(card.asImageBitmap(), contentDescription = "Brag card: $today steps today", modifier = Modifier.weight(1f).fillMaxWidth())
        Text("No location, no map, no metadata: just the picture.", color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.bodySmall)
        VeilButton("Share", { BragCard.share(context, card) }, glyph = ">")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            VeilButton("Save JPG", { note = if (BragCard.saveToGallery(context, card)) "saved to Pictures/VeilWalker" else "couldn't save" }, glyph = "v")
        }
        note?.let { Text(it, color = MaterialTheme.colorScheme.secondary, style = MaterialTheme.typography.bodySmall) }
        VeilButton("Back", onBack, glyph = "<")
    }
}
