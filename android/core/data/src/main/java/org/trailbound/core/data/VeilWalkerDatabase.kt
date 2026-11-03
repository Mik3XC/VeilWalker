package org.trailbound.core.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import org.trailbound.core.data.dao.AchievementDao
import org.trailbound.core.data.dao.LedgerDao
import org.trailbound.core.data.dao.StepDao
import org.trailbound.core.data.dao.SummaryDao
import org.trailbound.core.data.dao.TraceDao
import org.trailbound.core.data.dao.WalkDao
import org.trailbound.core.data.entity.AchievementUnlock
import org.trailbound.core.data.entity.CounterBaseline
import org.trailbound.core.data.entity.DailySummary
import org.trailbound.core.data.entity.LedgerEntry
import org.trailbound.core.data.entity.RawTrace
import org.trailbound.core.data.entity.StepInterval
import org.trailbound.core.data.entity.WalkSession
import javax.inject.Singleton

@Database(
    entities = [
        CounterBaseline::class, StepInterval::class, WalkSession::class, RawTrace::class,
        DailySummary::class, LedgerEntry::class, AchievementUnlock::class,
    ],
    version = 2,
    exportSchema = false,
)
abstract class VeilWalkerDatabase : RoomDatabase() {
    abstract fun stepDao(): StepDao
    abstract fun walkDao(): WalkDao
    abstract fun traceDao(): TraceDao
    abstract fun summaryDao(): SummaryDao
    abstract fun ledgerDao(): LedgerDao
    abstract fun achievementDao(): AchievementDao

    /**
     * The only sanctioned way to clear the ledger copy: when the user restores a different identity,
     * the old account's chain no longer belongs on this phone. Lifts the append-only triggers just for this.
     */
    fun resetLedger() {
        val w = openHelper.writableDatabase
        w.beginTransaction()
        try {
            w.execSQL("DROP TRIGGER IF EXISTS ledger_no_delete")
            w.execSQL("DELETE FROM ledger_entry")
            w.execSQL(LEDGER_NO_DELETE)
            w.execSQL("UPDATE daily_summary SET synced = 0")
            w.setTransactionSuccessful()
        } finally {
            w.endTransaction()
        }
    }
}

private const val LEDGER_NO_DELETE =
    "CREATE TRIGGER ledger_no_delete BEFORE DELETE ON ledger_entry BEGIN SELECT RAISE(ABORT, 'ledger is append-only'); END"

/** Enforce append-only at the SQLite level too, not just in the DAO. */
private val ledgerGuards = object : RoomDatabase.Callback() {
    override fun onCreate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TRIGGER ledger_no_update BEFORE UPDATE ON ledger_entry " +
                "BEGIN SELECT RAISE(ABORT, 'ledger is append-only'); END"
        )
        db.execSQL(LEDGER_NO_DELETE)
    }
}

/** v2: cold-walk climb and temperature per walk (Hidden Peaks). */
private val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE walk_session ADD COLUMN coldClimbM REAL NOT NULL DEFAULT 0")
        db.execSQL("ALTER TABLE walk_session ADD COLUMN minTempF INTEGER")
    }
}

@Module
@InstallIn(SingletonComponent::class)
object DataModule {
    @Provides @Singleton
    fun db(@ApplicationContext ctx: Context): VeilWalkerDatabase =
        Room.databaseBuilder(ctx, VeilWalkerDatabase::class.java, "trailbound.db") // file name kept from pre-rename builds so existing history survives
            .addCallback(ledgerGuards)
            .addMigrations(MIGRATION_1_2)
            .build()

    @Provides fun stepDao(db: VeilWalkerDatabase) = db.stepDao()
    @Provides fun walkDao(db: VeilWalkerDatabase) = db.walkDao()
    @Provides fun traceDao(db: VeilWalkerDatabase) = db.traceDao()
    @Provides fun summaryDao(db: VeilWalkerDatabase) = db.summaryDao()
    @Provides fun ledgerDao(db: VeilWalkerDatabase) = db.ledgerDao()
    @Provides fun achievementDao(db: VeilWalkerDatabase) = db.achievementDao()
}
