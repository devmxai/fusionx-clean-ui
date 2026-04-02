package com.fusionx.fusionx_clean_ui.engine

class FusionXTransport(
    private val events: FusionXEventDispatcher,
) {
    private val lock = Any()

    private var playbackState = FusionXPlaybackState.IDLE
    private var sourceDurationUs = 0L
    private var sourceWidth = 0
    private var sourceHeight = 0
    private var sourceFrameRate = 0f
    private var trimStartUs = 0L
    private var trimEndUs = 0L
    private var currentSourceTimeUs = 0L
    private var timelineOffsetUs = 0L

    fun emitReady(payload: Map<String, Any?> = emptyMap()) {
        events.emit("ready", payload)
    }

    fun onClipLoaded(
        sourceDurationUs: Long,
        sourceWidth: Int,
        sourceHeight: Int,
        sourceFrameRate: Float,
    ) {
        val durationPayload: Map<String, Any?>
        synchronized(lock) {
            updateSourceMetadataLocked(
                sourceDurationUs = sourceDurationUs,
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
                sourceFrameRate = sourceFrameRate,
            )
            trimStartUs = 0L
            trimEndUs = this.sourceDurationUs
            currentSourceTimeUs = trimStartUs
            durationPayload = buildDurationPayloadLocked()
        }
        events.emit("durationResolved", durationPayload)
        setPlaybackState(FusionXPlaybackState.READY)
        emitPositionChanged()
    }

    fun updateSourceMetadata(
        sourceDurationUs: Long,
        sourceWidth: Int,
        sourceHeight: Int,
        sourceFrameRate: Float,
    ) {
        synchronized(lock) {
            updateSourceMetadataLocked(
                sourceDurationUs = sourceDurationUs,
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
                sourceFrameRate = sourceFrameRate,
            )
        }
    }

    fun currentPlaybackState(): FusionXPlaybackState {
        synchronized(lock) {
            return playbackState
        }
    }

    fun setPlaybackState(nextState: FusionXPlaybackState) {
        val shouldEmit: Boolean
        synchronized(lock) {
            shouldEmit = playbackState != nextState
            playbackState = nextState
        }
        if (shouldEmit) {
            events.emit(
                "playbackStateChanged",
                mapOf("state" to nextState.wireName()),
            )
        }
    }

    fun currentSourceDurationUs(): Long {
        synchronized(lock) {
            return sourceDurationUs
        }
    }

    fun currentSourcePositionUs(): Long {
        synchronized(lock) {
            return currentSourceTimeUs
        }
    }

    fun currentTrimStartUs(): Long {
        synchronized(lock) {
            return trimStartUs
        }
    }

    fun currentTrimEndUs(): Long {
        synchronized(lock) {
            return trimEndUs
        }
    }

    fun currentTimelineTimeUs(): Long {
        synchronized(lock) {
            return sourceToTimelineTimeUsLocked(currentSourceTimeUs)
        }
    }

    fun currentTimelineOffsetUs(): Long {
        synchronized(lock) {
            return timelineOffsetUs
        }
    }

    fun setTimelineOffsetUs(timelineOffsetUs: Long) {
        synchronized(lock) {
            this.timelineOffsetUs = timelineOffsetUs.coerceAtLeast(0L)
        }
    }

    fun timelineToSourceTimeUs(timelineTimeUs: Long): Long {
        synchronized(lock) {
            val clipLocalTimeUs = (timelineTimeUs - timelineOffsetUs).coerceAtLeast(0L)
            return clampSourceTimeUsLocked(trimStartUs + clipLocalTimeUs)
        }
    }

    fun setSourcePositionUs(sourceTimeUs: Long, emitEvent: Boolean = true) {
        synchronized(lock) {
            currentSourceTimeUs = clampSourceTimeUsLocked(sourceTimeUs)
        }
        if (emitEvent) {
            emitPositionChanged()
        }
    }

    fun setTrimWindow(trimStartUs: Long, trimEndUs: Long) {
        setTrimWindow(
            trimStartUs = trimStartUs,
            trimEndUs = trimEndUs,
            anchorSourceTimeUs = null,
            emitEvents = true,
        )
    }

    fun setTrimWindow(
        trimStartUs: Long,
        trimEndUs: Long,
        anchorSourceTimeUs: Long?,
        emitEvents: Boolean,
    ) {
        val trimPayload: Map<String, Any?>
        val durationPayload: Map<String, Any?>
        val positionPayload: Map<String, Any?>
        synchronized(lock) {
            val clampedStart = trimStartUs.coerceIn(0L, sourceDurationUs)
            val clampedEnd = trimEndUs.coerceIn(clampedStart, sourceDurationUs)
            this.trimStartUs = clampedStart
            this.trimEndUs = clampedEnd
            currentSourceTimeUs = clampSourceTimeUsLocked(anchorSourceTimeUs ?: clampedStart)
            trimPayload = buildTrimPayloadLocked()
            durationPayload = buildDurationPayloadLocked()
            positionPayload = buildTimePayloadLocked(currentSourceTimeUs)
        }
        if (emitEvents) {
            events.emit("trimChanged", trimPayload)
            events.emit("durationResolved", durationPayload)
            events.emit("positionChanged", positionPayload)
        }
    }

    fun emitTrimWindowState() {
        val trimPayload: Map<String, Any?>
        val durationPayload: Map<String, Any?>
        val positionPayload: Map<String, Any?>
        synchronized(lock) {
            trimPayload = buildTrimPayloadLocked()
            durationPayload = buildDurationPayloadLocked()
            positionPayload = buildTimePayloadLocked(currentSourceTimeUs)
        }
        events.emit("trimChanged", trimPayload)
        events.emit("durationResolved", durationPayload)
        events.emit("positionChanged", positionPayload)
    }

    fun buildFirstFramePayload(): Map<String, Any?> {
        synchronized(lock) {
            return buildTimePayloadLocked(currentSourceTimeUs)
        }
    }

    private fun emitPositionChanged() {
        val payload: Map<String, Any?>
        synchronized(lock) {
            payload = buildTimePayloadLocked(currentSourceTimeUs)
        }
        events.emit("positionChanged", payload)
    }

    private fun buildDurationPayloadLocked(): Map<String, Any?> {
        return mapOf(
            "sourceDurationUs" to sourceDurationUs,
            "sourceWidth" to sourceWidth,
            "sourceHeight" to sourceHeight,
            "sourceFrameRate" to sourceFrameRate,
            "sourceFrameDurationUs" to resolveFrameDurationUsLocked(),
            "trimStartUs" to trimStartUs,
            "trimEndUs" to trimEndUs,
            "clipDurationUs" to (trimEndUs - trimStartUs).coerceAtLeast(0L),
            "timelineDurationUs" to (trimEndUs - trimStartUs).coerceAtLeast(0L),
            "timelineOffsetUs" to timelineOffsetUs,
            "timelineTimeUs" to sourceToTimelineTimeUsLocked(currentSourceTimeUs),
        )
    }

    private fun buildTrimPayloadLocked(): Map<String, Any?> {
        return mapOf(
            "trimStartUs" to trimStartUs,
            "trimEndUs" to trimEndUs,
            "clipDurationUs" to (trimEndUs - trimStartUs).coerceAtLeast(0L),
            "timelineOffsetUs" to timelineOffsetUs,
            "timelineTimeUs" to sourceToTimelineTimeUsLocked(currentSourceTimeUs),
        )
    }

    private fun buildTimePayloadLocked(sourceTimeUs: Long): Map<String, Any?> {
        val clipLocalTimeUs = (sourceTimeUs - trimStartUs).coerceAtLeast(0L)
        val projectTimelineTimeUs = timelineOffsetUs + clipLocalTimeUs
        return mapOf(
            "sourceTimeUs" to sourceTimeUs,
            "clipLocalTimeUs" to clipLocalTimeUs,
            "timelineTimeUs" to projectTimelineTimeUs,
            "timelineOffsetUs" to timelineOffsetUs,
        )
    }

    private fun sourceToTimelineTimeUsLocked(sourceTimeUs: Long): Long {
        val clipLocalTimeUs = (sourceTimeUs - trimStartUs).coerceAtLeast(0L)
        return timelineOffsetUs + clipLocalTimeUs
    }

    private fun resolveFrameDurationUsLocked(): Long {
        if (sourceFrameRate <= 0f) {
            return 0L
        }
        return (1_000_000f / sourceFrameRate).toLong().coerceAtLeast(1L)
    }

    private fun updateSourceMetadataLocked(
        sourceDurationUs: Long,
        sourceWidth: Int,
        sourceHeight: Int,
        sourceFrameRate: Float,
    ) {
        this.sourceDurationUs = sourceDurationUs.coerceAtLeast(0L)
        this.sourceWidth = sourceWidth.coerceAtLeast(0)
        this.sourceHeight = sourceHeight.coerceAtLeast(0)
        this.sourceFrameRate = sourceFrameRate.coerceAtLeast(0f)
    }

    private fun clampSourceTimeUsLocked(sourceTimeUs: Long): Long {
        if (sourceDurationUs <= 0L) {
            return 0L
        }
        return sourceTimeUs.coerceIn(trimStartUs, trimEndUs)
    }
}
