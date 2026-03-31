package com.fusionx.fusionx_clean_ui.engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.view.TextureRegistry

class FusionXEngineController(
    private val applicationContext: Context,
    private val textureRegistry: TextureRegistry,
    private val events: FusionXEventDispatcher,
) {
    private val lock = Any()
    private val transport = FusionXTransport(events)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var previewCoordinator: FusionXPreviewCoordinator? = null
    private var playbackSession: FusionXDecoderSession? = null
    private var scrubSession: FusionXScrubSession? = null
    private var scrubModeActive = false
    private var lastRequestedScrubTimelineTimeUs: Long? = null
    private var clipLoadGeneration = 0L
    private var pendingScrubPrepareRunnable: Runnable? = null

    fun attachRenderTarget(width: Int, height: Int): Long {
        synchronized(lock) {
            detachRenderTargetLocked()
            val nextPreviewCoordinator = FusionXPreviewCoordinator(
                textureRegistry = textureRegistry,
                width = width,
                height = height,
                events = events,
            )
            previewCoordinator = nextPreviewCoordinator
            transport.emitReady(
                mapOf(
                    "textureId" to nextPreviewCoordinator.activeTextureId(),
                    "renderTargetAttached" to true,
                    "previewMode" to "playback",
                ),
            )
            return nextPreviewCoordinator.activeTextureId()
        }
    }

    fun detachRenderTarget() {
        synchronized(lock) {
            detachRenderTargetLocked()
        }
    }

    fun loadClip(path: String) {
        val activePreviewCoordinator = synchronized(lock) {
            previewCoordinator
                ?: throw IllegalStateException("Attach a render target before loading a clip.")
        }
        val scrubTargetWidth = activePreviewCoordinator.scrubTarget().width
        val scrubTargetHeight = activePreviewCoordinator.scrubTarget().height

        synchronized(lock) {
            clipLoadGeneration += 1L
            val generation = clipLoadGeneration
            pendingScrubPrepareRunnable?.let(mainHandler::removeCallbacks)
            pendingScrubPrepareRunnable = null
            scrubSession?.release()
            scrubSession = null
            playbackSession?.release()
            playbackSession = FusionXDecoderSession(
                applicationContext = applicationContext,
                renderTarget = activePreviewCoordinator.playbackTarget(),
                transport = transport,
                events = events,
                onClipPrepared = {
                    scheduleScrubPreparation(
                        generation = generation,
                    )
                },
            )
            scrubSession = FusionXScrubSession(
                applicationContext = applicationContext,
                renderTarget = activePreviewCoordinator.scrubTarget(),
                transport = transport,
                events = events,
            )
            scrubSession?.loadClip(
                path = path,
                sourceWidth = scrubTargetWidth,
                sourceHeight = scrubTargetHeight,
            )
            scrubModeActive = false
            activePreviewCoordinator.activatePlayback()
            playbackSession?.loadClip(path)
            generation
        }
    }

    fun beginScrub() {
        synchronized(lock) {
            playbackSession ?: throw IllegalStateException("Load a clip before scrubbing.")
            scrubModeActive = true
            lastRequestedScrubTimelineTimeUs = transport.currentTimelineTimeUs()
            previewCoordinator?.activatePlayback(emitEvent = false)
        }
    }

    fun endScrub(targetTimelineTimeUs: Long? = null) {
        val activePlaybackSession: FusionXDecoderSession
        val activeScrubSession: FusionXScrubSession?
        val resolvedTargetTimelineTimeUs: Long
        synchronized(lock) {
            activePlaybackSession =
                playbackSession ?: throw IllegalStateException("Load a clip before scrubbing.")
            activeScrubSession = scrubSession
            resolvedTargetTimelineTimeUs =
                targetTimelineTimeUs
                    ?: lastRequestedScrubTimelineTimeUs
                    ?: transport.currentTimelineTimeUs()
        }
        activeScrubSession?.stopAndDrain()
        activePlaybackSession.stopAndDrainScrub()
        synchronized(lock) {
            scrubModeActive = false
            lastRequestedScrubTimelineTimeUs = null
            previewCoordinator?.activatePlayback()
        }
        activePlaybackSession.seekToTimelineTimeUs(resolvedTargetTimelineTimeUs)
    }

    fun play() {
        val activePlaybackSession: FusionXDecoderSession
        val activeScrubSession: FusionXScrubSession?
        synchronized(lock) {
            activePlaybackSession =
                playbackSession ?: throw IllegalStateException("Load a clip before playback.")
            activeScrubSession = scrubSession
        }
        activeScrubSession?.stopAndDrain()
        activePlaybackSession.stopAndDrainScrub()
        synchronized(lock) {
            scrubModeActive = false
            lastRequestedScrubTimelineTimeUs = null
            previewCoordinator?.activatePlayback()
        }
        activePlaybackSession.play()
    }

    fun pause() {
        synchronized(lock) {
            playbackSession?.pause()
        }
    }

    fun seekTo(timelineTimeUs: Long) {
        val activePlaybackSession: FusionXDecoderSession
        val activeScrubSession: FusionXScrubSession?
        synchronized(lock) {
            activePlaybackSession =
                playbackSession ?: throw IllegalStateException("Load a clip before seeking.")
            activeScrubSession = scrubSession
        }
        activeScrubSession?.stopAndDrain()
        activePlaybackSession.stopAndDrainScrub()
        synchronized(lock) {
            scrubModeActive = false
            lastRequestedScrubTimelineTimeUs = null
            previewCoordinator?.activatePlayback()
        }
        activePlaybackSession.seekToTimelineTimeUs(timelineTimeUs)
    }

    fun scrubTo(timelineTimeUs: Long) {
        val activeScrubSession: FusionXScrubSession?
        val activePlaybackSession: FusionXDecoderSession?
        synchronized(lock) {
            playbackSession ?: throw IllegalStateException("Load a clip before scrubbing.")
            if (!scrubModeActive) {
                scrubModeActive = true
            }
            lastRequestedScrubTimelineTimeUs = timelineTimeUs
            activeScrubSession = scrubSession
            activePlaybackSession = playbackSession
        }
        val handledByProxy = activeScrubSession?.requestScrubAtTimelineTimeUs(timelineTimeUs) == true
        if (!handledByProxy) {
            activePlaybackSession?.scrubToTimelineTimeUs(timelineTimeUs)
        }
    }

    fun setTrim(trimStartUs: Long, trimEndUs: Long) {
        val activePlaybackSession: FusionXDecoderSession
        val activeScrubSession: FusionXScrubSession?
        synchronized(lock) {
            activePlaybackSession =
                playbackSession ?: throw IllegalStateException("Load a clip before trimming.")
            activeScrubSession = scrubSession
        }
        activeScrubSession?.stopAndDrain()
        activePlaybackSession.stopAndDrainScrub()
        synchronized(lock) {
            scrubModeActive = false
            lastRequestedScrubTimelineTimeUs = null
            previewCoordinator?.activatePlayback()
        }
        activePlaybackSession.setTrim(trimStartUs, trimEndUs)
    }

    fun dispose() {
        synchronized(lock) {
            pendingScrubPrepareRunnable?.let(mainHandler::removeCallbacks)
            pendingScrubPrepareRunnable = null
            scrubSession?.release()
            scrubSession = null
            playbackSession?.release()
            playbackSession = null
            detachRenderTargetLocked()
        }
    }

    private fun scheduleScrubPreparation(generation: Long) {
        var prepareRunnable: Runnable? = null
        prepareRunnable = Runnable {
            val activeScrubSession = synchronized(lock) {
                if (clipLoadGeneration != generation) {
                    if (pendingScrubPrepareRunnable === prepareRunnable) {
                        pendingScrubPrepareRunnable = null
                    }
                    null
                } else {
                    if (pendingScrubPrepareRunnable === prepareRunnable) {
                        pendingScrubPrepareRunnable = null
                    }
                    scrubSession
                }
            } ?: return@Runnable
            activeScrubSession.prepareProxyIfNeeded()
        }

        synchronized(lock) {
            if (clipLoadGeneration != generation) {
                return
            }
            pendingScrubPrepareRunnable?.let(mainHandler::removeCallbacks)
            pendingScrubPrepareRunnable = prepareRunnable
        }
        val scheduledRunnable = prepareRunnable ?: return
        if (SCRUB_PREPARE_DELAY_MS <= 0L) {
            mainHandler.post(scheduledRunnable)
        } else {
            mainHandler.postDelayed(scheduledRunnable, SCRUB_PREPARE_DELAY_MS)
        }
    }

    private fun detachRenderTargetLocked() {
        pendingScrubPrepareRunnable?.let(mainHandler::removeCallbacks)
        pendingScrubPrepareRunnable = null
        scrubSession?.release()
        scrubSession = null
        playbackSession?.release()
        playbackSession = null
        previewCoordinator?.release()
        previewCoordinator = null
        scrubModeActive = false
        lastRequestedScrubTimelineTimeUs = null
    }

    companion object {
        private const val SCRUB_PREPARE_DELAY_MS = 0L
    }
}
