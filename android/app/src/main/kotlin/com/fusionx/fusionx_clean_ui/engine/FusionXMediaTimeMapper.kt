package com.fusionx.fusionx_clean_ui.engine

import kotlin.math.roundToLong

interface FusionXMediaTimeMapper {
    fun sourceToMediaTimeUs(sourceTimeUs: Long): Long

    fun mediaToSourceTimeUs(mediaTimeUs: Long): Long

    object Identity : FusionXMediaTimeMapper {
        override fun sourceToMediaTimeUs(sourceTimeUs: Long): Long = sourceTimeUs.coerceAtLeast(0L)

        override fun mediaToSourceTimeUs(mediaTimeUs: Long): Long = mediaTimeUs.coerceAtLeast(0L)
    }

    class DurationRatio(
        sourceDurationUs: Long,
        mediaDurationUs: Long,
    ) : FusionXMediaTimeMapper {
        private val safeSourceDurationUs = sourceDurationUs.coerceAtLeast(1L)
        private val safeMediaDurationUs = mediaDurationUs.coerceAtLeast(1L)

        override fun sourceToMediaTimeUs(sourceTimeUs: Long): Long {
            val clampedSourceTimeUs = sourceTimeUs.coerceIn(0L, safeSourceDurationUs)
            return ((clampedSourceTimeUs.toDouble() / safeSourceDurationUs.toDouble()) *
                safeMediaDurationUs.toDouble()).roundToLong()
        }

        override fun mediaToSourceTimeUs(mediaTimeUs: Long): Long {
            val clampedMediaTimeUs = mediaTimeUs.coerceIn(0L, safeMediaDurationUs)
            return ((clampedMediaTimeUs.toDouble() / safeMediaDurationUs.toDouble()) *
                safeSourceDurationUs.toDouble()).roundToLong()
        }
    }
}
