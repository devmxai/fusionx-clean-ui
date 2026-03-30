package com.fusionx.fusionx_clean_ui.engine

import android.content.Context
import io.flutter.view.TextureRegistry

class FusionXEngineController(
    private val applicationContext: Context,
    private val textureRegistry: TextureRegistry,
    private val events: FusionXEventDispatcher,
) {
    private val lock = Any()
    private val transport = FusionXTransport(events)
    private val vulkanBridge = FusionXVulkanBridge()

    private var previewCoordinator: FusionXPreviewCoordinator? = null
    private var playbackSession: FusionXDecoderSession? = null
    private var scrubSession: FusionXScrubSession? = null
    private var vulkanPreviewSession: FusionXVulkanPreviewSession? = null
    private var scrubModeActive = false
    private var lastRequestedScrubTimelineTimeUs: Long? = null

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
            vulkanPreviewSession = FusionXVulkanPreviewSession(
                renderTarget = nextPreviewCoordinator.playbackTarget(),
                bridge = vulkanBridge,
                events = events,
            ).also { previewSession ->
                previewSession.start()
            }
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

        synchronized(lock) {
            vulkanPreviewSession?.release()
            vulkanPreviewSession = null
            scrubSession?.release()
            scrubSession = null
            playbackSession?.release()
            playbackSession = FusionXDecoderSession(
                applicationContext = applicationContext,
                renderTarget = activePreviewCoordinator.playbackTarget(),
                transport = transport,
                events = events,
            )
            scrubSession = FusionXScrubSession(
                applicationContext = applicationContext,
                renderTarget = activePreviewCoordinator.scrubTarget(),
                transport = transport,
                events = events,
            )
            scrubModeActive = false
            activePreviewCoordinator.activatePlayback()
            playbackSession?.loadClip(path)
            scrubSession?.loadClip(
                path = path,
                sourceWidth = activePreviewCoordinator.scrubTarget().width,
                sourceHeight = activePreviewCoordinator.scrubTarget().height,
            )
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
            scrubSession?.release()
            scrubSession = null
            playbackSession?.release()
            playbackSession = null
            detachRenderTargetLocked()
        }
    }

    private fun detachRenderTargetLocked() {
        vulkanPreviewSession?.release()
        vulkanPreviewSession = null
        scrubSession?.release()
        scrubSession = null
        playbackSession?.release()
        playbackSession = null
        previewCoordinator?.release()
        previewCoordinator = null
        scrubModeActive = false
        lastRequestedScrubTimelineTimeUs = null
    }
}
