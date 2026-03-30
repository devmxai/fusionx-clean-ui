package com.fusionx.fusionx_clean_ui.engine

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.SystemClock
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

class FusionXDecoderSession(
    private val applicationContext: Context,
    private val renderTarget: FusionXRenderTarget,
    private val transport: FusionXTransport,
    private val events: FusionXEventDispatcher,
) {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val resourceLock = Any()
    private val scrubPreviewRenderer = FusionXScrubPreviewRenderer(
        applicationContext = applicationContext,
        renderTarget = renderTarget,
        transport = transport,
        events = events,
    )

    private var activeTask: Future<*>? = null
    private var extractor: MediaExtractor? = null
    private var decoder: MediaCodec? = null
    private var selectedTrackIndex = -1
    private var clipPath: String? = null
    private var firstFrameReported = false

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
        val targetSourceTimeUs = transport.timelineToSourceTimeUs(timelineTimeUs)
        scrubPreviewRenderer.requestFrame(targetSourceTimeUs)
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
        scrubPreviewRenderer.release()
        try {
            executor.submit {
                releaseCodecResourcesInternal()
            }.get(2, TimeUnit.SECONDS)
        } catch (_: Throwable) {
        } finally {
            executor.shutdownNow()
        }
    }

    private fun submitReplacingCurrentTask(block: () -> Unit) {
        scrubPreviewRenderer.cancelPending()
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
        localDecoder.configure(format, renderTarget.surface, null, 0)
        localDecoder.start()
        scrubPreviewRenderer.loadClip(path)

        synchronized(resourceLock) {
            extractor = localExtractor
            decoder = localDecoder
            selectedTrackIndex = trackIndex
            clipPath = path
            firstFrameReported = false
        }

        val durationUs = format.getLongSafely(MediaFormat.KEY_DURATION, 0L)
        transport.onClipLoaded(
            sourceDurationUs = durationUs,
            sourceWidth = width,
            sourceHeight = height,
        )
        renderFrameAtSourceTimeUsInternal(transport.currentTrimStartUs())
        transport.setPlaybackState(FusionXPlaybackState.PAUSED)
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
        prepareCodecForSourceTimeUs(playbackStartSourceTimeUs)
        transport.setPlaybackState(FusionXPlaybackState.PLAYING)

        val anchorRealtimeUs = SystemClock.elapsedRealtimeNanos() / 1000L
        val outputBufferInfo = MediaCodec.BufferInfo()
        var inputEnded = false

        while (!Thread.currentThread().isInterrupted) {
            val activeDecoder = requireDecoder()
            if (!inputEnded) {
                inputEnded = feedSingleInputBuffer(activeDecoder, trimEndUs)
            }

            val outputIndex = activeDecoder.dequeueOutputBuffer(outputBufferInfo, DEQUEUE_TIMEOUT_US)
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

                    val targetRealtimeUs =
                        anchorRealtimeUs + (frameSourceTimeUs - playbackStartSourceTimeUs)
                    sleepUntil(targetRealtimeUs)
                    ensureNotInterrupted()

                    activeDecoder.releaseOutputBuffer(outputIndex, true)
                    transport.setSourcePositionUs(frameSourceTimeUs)
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

    private fun renderFrameAtSourceTimeUsInternal(targetSourceTimeUs: Long) {
        ensureLoaded()
        prepareCodecForSourceTimeUs(targetSourceTimeUs)

        val outputBufferInfo = MediaCodec.BufferInfo()
        val trimEndUs = transport.currentTrimEndUs()
        var inputEnded = false

        while (!Thread.currentThread().isInterrupted) {
            val activeDecoder = requireDecoder()
            if (!inputEnded) {
                inputEnded = feedSingleInputBuffer(activeDecoder, trimEndUs)
            }

            val outputIndex = activeDecoder.dequeueOutputBuffer(outputBufferInfo, DEQUEUE_TIMEOUT_US)
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
                        transport.setSourcePositionUs(resolvedSourceTimeUs)
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

    private fun prepareCodecForSourceTimeUs(sourceTimeUs: Long) {
        val activeExtractor = requireExtractor()
        val activeDecoder = requireDecoder()
        activeExtractor.seekTo(sourceTimeUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        activeDecoder.flush()
    }

    private fun feedSingleInputBuffer(
        activeDecoder: MediaCodec,
        trimEndUs: Long,
    ): Boolean {
        val activeExtractor = requireExtractor()
        val inputIndex = activeDecoder.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
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
        private const val DEQUEUE_TIMEOUT_US = 10_000L
    }
}
