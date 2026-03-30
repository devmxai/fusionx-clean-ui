package com.fusionx.fusionx_clean_ui.engine

class FusionXTransport(
    private val events: FusionXEventDispatcher,
) {
    private val lock = Any()

    private var playbackState = FusionXPlaybackState.IDLE
    private var sourceDurationUs = 0L
    private var sourceWidth = 0
    private var sourceHeight = 0
    private var trimStartUs = 0L
    private var trimEndUs = 0L
    private var currentSourceTimeUs = 0L

    fun emitReady(payload: Map<String, Any?> = emptyMap()) {
        events.emit("ready", payload)
    }

    fun onClipLoaded(
        sourceDurationUs: Long,
        sourceWidth: Int,
        sourceHeight: Int,
    ) {
        val durationPayload: Map<String, Any?>
        synchronized(lock) {
            this.sourceDurationUs = sourceDurationUs.coerceAtLeast(0L)
            this.sourceWidth = sourceWidth.coerceAtLeast(0)
            this.sourceHeight = sourceHeight.coerceAtLeast(0)
            trimStartUs = 0L
            trimEndUs = this.sourceDurationUs
            currentSourceTimeUs = trimStartUs
            durationPayload = buildDurationPayloadLocked()
        }
        events.emit("durationResolved", durationPayload)
        setPlaybackState(FusionXPlaybackState.READY)
        emitPositionChanged()
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

    fun timelineToSourceTimeUs(timelineTimeUs: Long): Long {
        synchronized(lock) {
            return clampSourceTimeUsLocked(trimStartUs + timelineTimeUs.coerceAtLeast(0L))
        }
    }

    fun setSourcePositionUs(sourceTimeUs: Long) {
        synchronized(lock) {
            currentSourceTimeUs = clampSourceTimeUsLocked(sourceTimeUs)
        }
        emitPositionChanged()
    }

    fun setTrimWindow(trimStartUs: Long, trimEndUs: Long) {
        val trimPayload: Map<String, Any?>
        val durationPayload: Map<String, Any?>
        synchronized(lock) {
            val clampedStart = trimStartUs.coerceIn(0L, sourceDurationUs)
            val clampedEnd = trimEndUs.coerceIn(clampedStart, sourceDurationUs)
            this.trimStartUs = clampedStart
            this.trimEndUs = clampedEnd
            currentSourceTimeUs = clampedStart
            trimPayload = buildTrimPayloadLocked()
            durationPayload = buildDurationPayloadLocked()
        }
        events.emit("trimChanged", trimPayload)
        events.emit("durationResolved", durationPayload)
        emitPositionChanged()
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
            "trimStartUs" to trimStartUs,
            "trimEndUs" to trimEndUs,
            "clipDurationUs" to (trimEndUs - trimStartUs).coerceAtLeast(0L),
            "timelineDurationUs" to (trimEndUs - trimStartUs).coerceAtLeast(0L),
        )
    }

    private fun buildTrimPayloadLocked(): Map<String, Any?> {
        return mapOf(
            "trimStartUs" to trimStartUs,
            "trimEndUs" to trimEndUs,
            "clipDurationUs" to (trimEndUs - trimStartUs).coerceAtLeast(0L),
        )
    }

    private fun buildTimePayloadLocked(sourceTimeUs: Long): Map<String, Any?> {
        val clipLocalTimeUs = sourceToTimelineTimeUsLocked(sourceTimeUs)
        return mapOf(
            "sourceTimeUs" to sourceTimeUs,
            "clipLocalTimeUs" to clipLocalTimeUs,
            "timelineTimeUs" to clipLocalTimeUs,
        )
    }

    private fun sourceToTimelineTimeUsLocked(sourceTimeUs: Long): Long {
        return (sourceTimeUs - trimStartUs).coerceAtLeast(0L)
    }

    private fun clampSourceTimeUsLocked(sourceTimeUs: Long): Long {
        if (sourceDurationUs <= 0L) {
            return 0L
        }
        return sourceTimeUs.coerceIn(trimStartUs, trimEndUs)
    }
}
