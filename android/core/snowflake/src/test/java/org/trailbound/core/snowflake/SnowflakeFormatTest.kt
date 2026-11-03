package org.trailbound.core.snowflake

import org.junit.Assert.assertEquals
import org.junit.Test

class SnowflakeFormatTest {
    @Test fun bytes() = assertEquals("0 B", SnowflakeController.format(0))
    @Test fun kilobytes() = assertEquals("512 KB", SnowflakeController.format(512_000))
    @Test fun megabytes() = assertEquals("41.2 MB", SnowflakeController.format(41_200_000))
    @Test fun gigabytes() = assertEquals("1.30 GB", SnowflakeController.format(1_300_000_000))
    @Test fun capsAreDecimal() {
        assertEquals(50_000_000L, SnowflakeController.SOFT_CAP)
        assertEquals(150_000_000L, SnowflakeController.HARD_CAP)
        assertEquals(500_000_000L, SnowflakeController.DAILY_CAP)
    }
}
