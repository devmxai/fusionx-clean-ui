package com.fusionx.fusionx_clean_ui.engine

import android.content.Context
import android.os.Build
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.SystemClock
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import kotlin.math.abs

class FusionXDecoderSession(
    private val applicationContext: Context,
    private val renderTarget: FusionXRenderTarget,
    private val transport: FusionXTransport,
    private val events: FusionXEventDispatcher,
    private val announceClipLoaded: Boolean = true,
    private val onClipPrepared: (() -> Unit)? = null,
    private val renderInitialFrameOnLoad: Boolean = true,
) {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val resourceLock = Any()
    private val scrubLock = Any()

    private var activeTask: Future<*>? = null
    private var scrubTask: Future<*>? = null
    private var extractor: MediaExtractor? = null
    private var decoder: MediaCodec? = null
    private var selectedTrackIndex = -1
    private var clipPath: String? = null
    private var firstFrameReported = false
    private var pendingScrubSourceTimeUs: Long? = null
    private var scrubWorkerScheduled = false
    private var decoderContinuationReady = false
    private var decoderLastRenderedSourceTimeUs = 0L

    fun loadClip(path: String) {
        submitReplacingCurrentTask {
            releaseCodecResourcesInternal()
            loadClipInternal(path)
        }
    }

    fun play() {
        submitReplacingCurrentTask {
            playInternal()
        }
    }

    fun pause() {
        cancelActiveTask()
        cancelScrubTask()
        transport.setPlaybackState(FusionXPlaybackState.PAUSED)
    }

    fun seekToTimelineTimeUs(timelineTimeUs: Long) {
        val resumePlayback = transport.currentPlaybackState() == FusionXPlaybackState.PLAYING
        submitReplacingCurrentTask {
            transport.setPlaybackState(FusionXPlaybackState.SEEKING)
            val targetSourceTimeUs = transport.timelineToSourceTimeUs(timelineTimeUs)
            renderFrameAtSourceTimeUsInternal(targetSourceTimeUs)
            if (resumePlayback) {
                playInternal()
            } else {
                transport.setPlaybackState(FusionXPlaybackState.PAUSED)
            }
        }
    }

    fun scrubToTimelineTimeUs(timelineTimeUs: Long) {
        cancelActiveTask()
        val targetSourceTimeUs = transport.timelineToSourceTimeUs(timelineTimeUs)
        enqueueScrubSourceTimeUs(targetSourceTimeUs)
    }

    fun setTrim(trimStartUs: Long, trimEndUs: Long) {
        val resumePlayback = transport.currentPlaybackState() == FusionXPlaybackState.PLAYING
        submitReplacingCurrentTask {
            transport.setTrimWindow(trimStartUs, trimEndUs)
            renderFrameAtSourceTimeUsInternal(transport.currentSourcePositionUs())
            if (resumePlayback) {
                playInternal()
            } else {
                transport.setPlaybackState(FusionXPlaybackState.PAUSED)
            }
        }
    }

    fun release() {
        cancelActiveTask()
        cancelScrubTask()
        try {
            executor.submit {
                releaseCodecResourcesInternal()
            }.get(2, TimeUnit.SECONDS)
        } catch (_: Throwable) {
        } finally {
            executor.shutdownNow()
        }
    }

    fun stopAndDrainScrub(timeoutMs: Long = 250L) {
        cancelActiveTask()
        cancelScrubTask()
        try {
            executor.submit {}.get(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: Throwable) {
        } finally {
            activeTask = null
            scrubTask = null
        }
    }

    private fun submitReplacingCurrentTask(block: () -> Unit) {
        cancelScrubTask()
        cancelActiveTask()
        activeTask = executor.submit {
            try {
                block()
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } catch (throwable: Throwable) {
                transport.setPlaybackState(FusionXPlaybackState.ERROR)
                emitError(
                    throwable.message ?: "Unknown decoder error",
                )
            }
        }
    }

    private fun cancelActiveTask() {
        activeTask?.cancel(true)
        activeTask = null
    }

    private fun cancelScrubTask() {
        synchronized(scrubLock) {
            pendingScrubSourceTimeUs = null
        }
        scrubTask?.cancel(true)
        scrubTask = null
    }

    private fun enqueueScrubSourceTimeUs(sourceTimeUs: Long) {
        synchronized(scrubLock) {
            pendingScrubSourceTimeUs = sourceTimeUs.coerceAtLeast(0L)
            if (scrubWorkerScheduled) {
                return
            }
            scrubWorkerScheduled = true
        }

        scrubTask = executor.submit {
            try {
                processScrubLoop()
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            } catch (throwable: Throwable) {
                transport.setPlaybackState(FusionXPlaybackState.ERROR)
                emitError(
                    throwable.message ?: "Unknown decoder error",
                )
            } finally {
                val shouldRestart = synchronized(scrubLock) {
                    scrubWorkerScheduled = false
                    pendingScrubSourceTimeUs != null
                }
                if (shouldRestart && !executor.isShutdown) {
                    val nextSourceTimeUs = synchronized(scrubLock) {
                        pendingScrubSourceTimeUs ?: 0L
                    }
                    enqueueScrubSourceTimeUs(nextSourceTimeUs)
                }
            }
        }
    }

    @Throws(InterruptedException::class)
    private fun processScrubLoop() {
        while (!Thread.currentThread().isInterrupted) {
            var targetSourceTimeUs = consumePendingScrubSourceTimeUs() ?: return
            var currentDecodedSourceTimeUs = transport.currentSourcePositionUs()
            var streamCanContinue = canContinueDecoderFrom(currentDecodedSourceTimeUs)

            transport.setPlaybackState(FusionXPlaybackState.PAUSED)
            while (!Thread.currentThread().isInterrupted) {
                if (!streamCanContinue ||
                    shouldReprepareScrub(
                        targetSourceTimeUs = targetSourceTimeUs,
                        currentDecodedSourceTimeUs = currentDecodedSourceTimeUs,
                    )
                ) {
                    currentDecodedSourceTimeUs = prepareCodecForSourceTimeUs(targetSourceTimeUs)
                    streamCanContinue = true
                }

                val result = decodeScrubTargetInternal(
                    initialTargetSourceTimeUs = targetSourceTimeUs,
                    currentDecodedSourceTimeUs = currentDecodedSourceTimeUs,
                )
                currentDecodedSourceTimeUs = result.lastDecodedSourceTimeUs
                if (result.requiresPrepare) {
                    targetSourceTimeUs = consumePendingScrubSourceTimeUs()
                        ?: result.nextTargetSourceTimeUs
                        ?: return
                    streamCanContinue = false
                    continue
                }

                targetSourceTimeUs = consumePendingScrubSourceTimeUs() ?: return
                streamCanContinue = !shouldReprepareScrub(
                    targetSourceTimeUs = targetSourceTimeUs,
                    currentDecodedSourceTimeUs = currentDecodedSourceTimeUs,
                )
            }
        }
    }

    @Throws(InterruptedException::class)
    private fun decodeScrubTargetInternal(
        initialTargetSourceTimeUs: Long,
        currentDecodedSourceTimeUs: Long,
    ): ScrubDecodeResult {
        val outputBufferInfo = MediaCodec.BufferInfo()
        val trimEndUs = transport.currentTrimEndUs()
        var inputEnded = false
        var targetSourceTimeUs = initialTargetSourceTimeUs
        var lastDecodedSourceTimeUs = currentDecodedSourceTimeUs
        var lastProgressiveRenderedSourceTimeUs = currentDecodedSourceTimeUs

        while (!Thread.currentThread().isInterrupted) {
            val pendingBeforeInput = consumePendingScrubSourceTimeUs()
            if (pendingBeforeInput != null) {
                if (shouldReprepareScrub(
                        targetSourceTimeUs = pendingBeforeInput,
                        currentDecodedSourceTimeUs = lastDecodedSourceTimeUs,
                    )
                ) {
                    return ScrubDecodeResult(
                        lastDecodedSourceTimeUs = lastDecodedSourceTimeUs,
                        nextTargetSourceTimeUs = pendingBeforeInput,
                        requiresPrepare = true,
                    )
                }
                targetSourceTimeUs = pendingBeforeInput
            }

            val activeDecoder = requireDecoder()
            if (!inputEnded) {
                inputEnded = feedSingleInputBuffer(
                    activeDecoder = activeDecoder,
                    trimEndUs = trimEndUs,
                    dequeueTimeoutUs = SCRUB_DEQUEUE_TIMEOUT_US,
                )
            }

            val outputIndex =
                activeDecoder.dequeueOutputBuffer(outputBufferInfo, SCRUB_DEQUEUE_TIMEOUT_US)
            when {
                outputIndex >= 0 -> {
                    val frameSourceTimeUs = outputBufferInfo.presentationTimeUs
                    lastDecodedSourceTimeUs = frameSourceTimeUs

                    val pendingAfterOutput = consumePendingScrubSourceTimeUs()
                    if (pendingAfterOutput != null) {
                        if (shouldReprepareScrub(
                                targetSourceTimeUs = pendingAfterOutput,
                                currentDecodedSourceTimeUs = lastDecodedSourceTimeUs,
                            )
                        ) {
                            activeDecoder.releaseOutputBuffer(outputIndex, false)
                            return ScrubDecodeResult(
                                lastDecodedSourceTimeUs = lastDecodedSourceTimeUs,
                                nextTargetSourceTimeUs = pendingAfterOutput,
                                requiresPrepare = true,
                            )
                        }
                        targetSourceTimeUs = pendingAfterOutput
                    }

                    val reachedEndOfStream =
                        (outputBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 ||
                            frameSourceTimeUs > trimEndUs
                    val reachedTarget = frameSourceTimeUs >= targetSourceTimeUs || reachedEndOfStream
                    val progressiveLagUs = (targetSourceTimeUs - frameSourceTimeUs).coerceAtLeast(0L)
                    val shouldRenderProgressive =
                        !reachedTarget &&
                            progressiveLagUs <= SCRUB_PROGRESSIVE_TARGET_WINDOW_US &&
                            frameSourceTimeUs > lastProgressiveRenderedSourceTimeUs &&
                            (frameSourceTimeUs - lastProgressiveRenderedSourceTimeUs) >=
                                SCRUB_PROGRESSIVE_RENDER_STEP_US
                    val shouldRender = reachedTarget || shouldRenderProgressive

                    val previousFrameSequence = if (shouldRender) {
                        renderTarget.currentFrameSequence()
                    } else {
                        -1L
                    }
                    activeDecoder.releaseOutputBuffer(outputIndex, shouldRender)
                    if (shouldRender) {
                        renderTarget.awaitNextFrame(
                            previousFrameSequence = previousFrameSequence,
                            timeoutMs = SCRUB_FRAME_PRESENT_TIMEOUT_MS,
                        )
                        val resolvedSourceTimeUs = if (reachedEndOfStream) {
                            trimEndUs
                        } else {
                            frameSourceTimeUs.coerceIn(
                                transport.currentTrimStartUs(),
                                transport.currentTrimEndUs(),
                            )
                        }
                        transport.setSourcePositionUs(
                            resolvedSourceTimeUs,
                            emitEvent = false,
                        )
                        markDecoderContinuationReady(resolvedSourceTimeUs)
                        emitFirstFrameIfNeeded()
                        lastProgressiveRenderedSourceTimeUs = resolvedSourceTimeUs
                        if (reachedTarget) {
                            return ScrubDecodeResult(
                                lastDecodedSourceTimeUs = resolvedSourceTimeUs,
                                nextTargetSourceTimeUs = null,
                                requiresPrepare = false,
                            )
                        }
                    }
                }

                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (inputEnded) {
                        if (lastDecodedSourceTimeUs > currentDecodedSourceTimeUs) {
                            val resolvedSourceTimeUs = lastDecodedSourceTimeUs.coerceIn(
                                transport.currentTrimStartUs(),
                                transport.currentTrimEndUs(),
                            )
                            transport.setSourcePositionUs(
                                resolvedSourceTimeUs,
                                emitEvent = false,
                            )
                            markDecoderContinuationReady(resolvedSourceTimeUs)
                            return ScrubDecodeResult(
                                lastDecodedSourceTimeUs = resolvedSourceTimeUs,
                                nextTargetSourceTimeUs = null,
                                requiresPrepare = false,
                            )
                        }
                        return ScrubDecodeResult(
                            lastDecodedSourceTimeUs = lastDecodedSourceTimeUs,
                            nextTargetSourceTimeUs = targetSourceTimeUs,
                            requiresPrepare = true,
                        )
                    }
                }

                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                outputIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
            }
        }

        throw InterruptedException()
    }

    private fun loadClipInternal(path: String) {
        val localExtractor = MediaExtractor()
        if (path.startsWith("content://") || path.startsWith("file://")) {
            localExtractor.setDataSource(applicationContext, Uri.parse(path), null)
        } else {
            localExtractor.setDataSource(path)
        }

        val trackIndex = findFirstVideoTrack(localExtractor)
        require(trackIndex >= 0) { "No video track found in clip." }

        val format = localExtractor.getTrackFormat(trackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)
        require(!mime.isNullOrBlank()) { "Missing MIME type for selected video track." }

        localExtractor.selectTrack(trackIndex)

        val width = format.getIntegerSafely(MediaFormat.KEY_WIDTH, 720)
        val height = format.getIntegerSafely(MediaFormat.KEY_HEIGHT, 1280)
        renderTarget.resize(width, height)

        val localDecoder = MediaCodec.createDecoderByType(mime)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
        }
        localDecoder.configure(format, renderTarget.surface, null, 0)
        localDecoder.start()
        synchronized(resourceLock) {
            extractor = localExtractor
            decoder = localDecoder
            selectedTrackIndex = trackIndex
            clipPath = path
            firstFrameReported = false
        }

        val durationUs = format.getLongSafely(MediaFormat.KEY_DURATION, 0L)
        if (announceClipLoaded) {
            transport.onClipLoaded(
                sourceDurationUs = durationUs,
                sourceWidth = width,
                sourceHeight = height,
            )
        }
        if (renderInitialFrameOnLoad) {
            renderFrameAtSourceTimeUsInternal(transport.currentTrimStartUs())
        }
        onClipPrepared?.invoke()
        if (announceClipLoaded) {
            transport.setPlaybackState(FusionXPlaybackState.PAUSED)
        }
    }

    private fun playInternal() {
        ensureLoaded()
        val trimStartUs = transport.currentTrimStartUs()
        val trimEndUs = transport.currentTrimEndUs()
        val currentSourceTimeUs = transport.currentSourcePositionUs()
        val playbackStartSourceTimeUs = when {
            trimEndUs <= trimStartUs -> trimStartUs
            currentSourceTimeUs >= trimEndUs -> trimStartUs
            currentSourceTimeUs < trimStartUs -> trimStartUs
            else -> currentSourceTimeUs
        }
        transport.setSourcePositionUs(playbackStartSourceTimeUs)
        if (!canContinueDecoderFrom(playbackStartSourceTimeUs)) {
            prepareCodecForSourceTimeUs(playbackStartSourceTimeUs)
        }
        transport.setPlaybackState(FusionXPlaybackState.PLAYING)

        val outputBufferInfo = MediaCodec.BufferInfo()
        var inputEnded = false
        var anchorRealtimeUs: Long? = null
        var anchorSourceTimeUs: Long? = null

        while (!Thread.currentThread().isInterrupted) {
            val activeDecoder = requireDecoder()
            if (!inputEnded) {
                inputEnded = feedSingleInputBuffer(
                    activeDecoder = activeDecoder,
                    trimEndUs = trimEndUs,
                    dequeueTimeoutUs = PLAY_DEQUEUE_TIMEOUT_US,
                )
            }

            val outputIndex =
                activeDecoder.dequeueOutputBuffer(outputBufferInfo, PLAY_DEQUEUE_TIMEOUT_US)
            when {
                outputIndex >= 0 -> {
                    val frameSourceTimeUs = outputBufferInfo.presentationTimeUs
                    if (frameSourceTimeUs < playbackStartSourceTimeUs) {
                        activeDecoder.releaseOutputBuffer(outputIndex, false)
                        continue
                    }

                    if ((outputBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 ||
                        frameSourceTimeUs > trimEndUs
                    ) {
                        activeDecoder.releaseOutputBuffer(outputIndex, false)
                        transport.setSourcePositionUs(trimEndUs)
                        transport.setPlaybackState(FusionXPlaybackState.COMPLETED)
                        return
                    }

                    if (anchorRealtimeUs == null || anchorSourceTimeUs == null) {
                        anchorRealtimeUs = SystemClock.elapsedRealtimeNanos() / 1000L
                        anchorSourceTimeUs = frameSourceTimeUs
                    }
                    val playbackAnchorRealtimeUs = anchorRealtimeUs ?: 0L
                    val playbackAnchorSourceUs = anchorSourceTimeUs ?: frameSourceTimeUs
                    val targetRealtimeUs =
                        playbackAnchorRealtimeUs + (frameSourceTimeUs - playbackAnchorSourceUs)
                    sleepUntil(targetRealtimeUs)
                    ensureNotInterrupted()

                    activeDecoder.releaseOutputBuffer(outputIndex, true)
                    transport.setSourcePositionUs(frameSourceTimeUs)
                    markDecoderContinuationReady(frameSourceTimeUs)
                    emitFirstFrameIfNeeded()
                }

                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (inputEnded) {
                        return
                    }
                }

                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                outputIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
            }
        }
    }

    private fun renderFrameAtSourceTimeUsInternal(
        targetSourceTimeUs: Long,
        emitPositionEvent: Boolean = true,
        dequeueTimeoutUs: Long = PLAY_DEQUEUE_TIMEOUT_US,
    ) {
        ensureLoaded()
        prepareCodecForSourceTimeUs(targetSourceTimeUs)

        val outputBufferInfo = MediaCodec.BufferInfo()
        val trimEndUs = transport.currentTrimEndUs()
        var inputEnded = false

        while (!Thread.currentThread().isInterrupted) {
            val activeDecoder = requireDecoder()
            if (!inputEnded) {
                inputEnded = feedSingleInputBuffer(
                    activeDecoder = activeDecoder,
                    trimEndUs = trimEndUs,
                    dequeueTimeoutUs = dequeueTimeoutUs,
                )
            }

            val outputIndex = activeDecoder.dequeueOutputBuffer(outputBufferInfo, dequeueTimeoutUs)
            when {
                outputIndex >= 0 -> {
                    val frameSourceTimeUs = outputBufferInfo.presentationTimeUs
                    val shouldRender =
                        frameSourceTimeUs >= targetSourceTimeUs ||
                            (outputBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0

                    activeDecoder.releaseOutputBuffer(outputIndex, shouldRender)
                    if (shouldRender) {
                        val resolvedSourceTimeUs = frameSourceTimeUs.coerceIn(
                            transport.currentTrimStartUs(),
                            transport.currentTrimEndUs(),
                        )
                        transport.setSourcePositionUs(
                            resolvedSourceTimeUs,
                            emitEvent = emitPositionEvent,
                        )
                        markDecoderContinuationReady(resolvedSourceTimeUs)
                        emitFirstFrameIfNeeded()
                        return
                    }
                }

                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (inputEnded) {
                        return
                    }
                }

                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                outputIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED -> Unit
            }
        }
    }

    private fun prepareCodecForSourceTimeUs(sourceTimeUs: Long): Long {
        val activeExtractor = requireExtractor()
        val activeDecoder = requireDecoder()
        activeExtractor.seekTo(sourceTimeUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        val preparedSourceTimeUs = activeExtractor.sampleTime.coerceAtLeast(0L)
        activeDecoder.flush()
        clearDecoderContinuationReady()
        return preparedSourceTimeUs
    }

    private fun feedSingleInputBuffer(
        activeDecoder: MediaCodec,
        trimEndUs: Long,
        dequeueTimeoutUs: Long,
    ): Boolean {
        val activeExtractor = requireExtractor()
        val inputIndex = activeDecoder.dequeueInputBuffer(dequeueTimeoutUs)
        if (inputIndex < 0) {
            return false
        }

        val inputBuffer = activeDecoder.getInputBuffer(inputIndex)
            ?: throw IllegalStateException("Decoder input buffer is unavailable.")

        val sampleSize = activeExtractor.readSampleData(inputBuffer, 0)
        val sourceTimeUs = activeExtractor.sampleTime
        if (sampleSize < 0 || sourceTimeUs < 0L || sourceTimeUs > trimEndUs) {
            activeDecoder.queueInputBuffer(
                inputIndex,
                0,
                0,
                0L,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
            )
            return true
        }

        activeDecoder.queueInputBuffer(
            inputIndex,
            0,
            sampleSize,
            sourceTimeUs,
            0,
        )
        activeExtractor.advance()
        return false
    }

    private fun emitFirstFrameIfNeeded() {
        if (firstFrameReported) {
            return
        }
        firstFrameReported = true
        events.emit("firstFrameRendered", transport.buildFirstFramePayload())
    }

    private fun ensureLoaded() {
        synchronized(resourceLock) {
            require(extractor != null && decoder != null && selectedTrackIndex >= 0) {
                "No clip has been loaded into the decoder session yet."
            }
        }
    }

    private fun requireExtractor(): MediaExtractor {
        synchronized(resourceLock) {
            return extractor ?: throw IllegalStateException("MediaExtractor is not ready.")
        }
    }

    private fun requireDecoder(): MediaCodec {
        synchronized(resourceLock) {
            return decoder ?: throw IllegalStateException("MediaCodec is not ready.")
        }
    }

    private fun releaseCodecResourcesInternal() {
        synchronized(resourceLock) {
            try {
                decoder?.stop()
            } catch (_: Throwable) {
            }
            try {
                decoder?.release()
            } catch (_: Throwable) {
            }
            try {
                extractor?.release()
            } catch (_: Throwable) {
            }
            decoder = null
            extractor = null
            selectedTrackIndex = -1
            clipPath = null
            firstFrameReported = false
            decoderContinuationReady = false
            decoderLastRenderedSourceTimeUs = 0L
        }
    }

    private fun peekPendingScrubSourceTimeUs(): Long? {
        synchronized(scrubLock) {
            return pendingScrubSourceTimeUs
        }
    }

    private fun consumePendingScrubSourceTimeUs(): Long? {
        synchronized(scrubLock) {
            val next = pendingScrubSourceTimeUs
            pendingScrubSourceTimeUs = null
            return next
        }
    }

    private fun shouldReprepareScrub(
        targetSourceTimeUs: Long,
        currentDecodedSourceTimeUs: Long,
    ): Boolean {
        val safeTargetSourceTimeUs = targetSourceTimeUs.coerceAtLeast(0L)
        if (safeTargetSourceTimeUs < currentDecodedSourceTimeUs) {
            return true
        }
        return (safeTargetSourceTimeUs - currentDecodedSourceTimeUs) >
            SCRUB_FORWARD_CONTINUATION_WINDOW_US
    }

    private fun canContinueDecoderFrom(sourceTimeUs: Long): Boolean {
        synchronized(resourceLock) {
            return decoderContinuationReady &&
                abs(decoderLastRenderedSourceTimeUs - sourceTimeUs) <=
                    DECODER_CONTINUATION_TOLERANCE_US
        }
    }

    private fun markDecoderContinuationReady(sourceTimeUs: Long) {
        synchronized(resourceLock) {
            decoderContinuationReady = true
            decoderLastRenderedSourceTimeUs = sourceTimeUs
        }
    }

    private fun clearDecoderContinuationReady() {
        synchronized(resourceLock) {
            decoderContinuationReady = false
        }
    }

    private fun emitError(message: String) {
        events.emit(
            "error",
            mapOf("message" to message),
        )
    }

    private fun sleepUntil(targetRealtimeUs: Long) {
        while (!Thread.currentThread().isInterrupted) {
            val nowUs = SystemClock.elapsedRealtimeNanos() / 1000L
            val remainingUs = targetRealtimeUs - nowUs
            if (remainingUs <= 0L) {
                return
            }
            if (remainingUs >= 2000L) {
                Thread.sleep(remainingUs / 1000L)
            } else {
                Thread.yield()
            }
        }
    }

    @Throws(InterruptedException::class)
    private fun ensureNotInterrupted() {
        if (Thread.currentThread().isInterrupted) {
            throw InterruptedException()
        }
    }

    private fun findFirstVideoTrack(extractor: MediaExtractor): Int {
        for (trackIndex in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(trackIndex)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("video/")) {
                return trackIndex
            }
        }
        return -1
    }

    private fun MediaFormat.getIntegerSafely(key: String, defaultValue: Int): Int {
        return if (containsKey(key)) getInteger(key) else defaultValue
    }

    private fun MediaFormat.getLongSafely(key: String, defaultValue: Long): Long {
        return if (containsKey(key)) getLong(key) else defaultValue
    }

    companion object {
        private const val PLAY_DEQUEUE_TIMEOUT_US = 10_000L
        private const val SCRUB_DEQUEUE_TIMEOUT_US = 2_000L
        private const val SCRUB_FORWARD_CONTINUATION_WINDOW_US = 6_000_000L
        private const val SCRUB_PROGRESSIVE_RENDER_STEP_US = 16_667L
        private const val SCRUB_PROGRESSIVE_TARGET_WINDOW_US = 120_000L
        private const val SCRUB_FRAME_PRESENT_TIMEOUT_MS = 24L
        private const val DECODER_CONTINUATION_TOLERANCE_US = 50_000L
    }

    private data class ScrubDecodeResult(
        val lastDecodedSourceTimeUs: Long,
        val nextTargetSourceTimeUs: Long?,
        val requiresPrepare: Boolean,
    )
}
