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
    private val timelineProjectStore = FusionXTimelineProjectStore()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var previewCoordinator: FusionXPreviewCoordinator? = null
    private var playbackSession: FusionXDecoderSession? = null
    private var scrubSession: FusionXScrubSession? = null
    private var scrubModeActive = false
    private var lastRequestedScrubTimelineTimeUs: Long? = null
    private var clipLoadGeneration = 0L
    private var pendingScrubPrepareRunnable: Runnable? = null
    private var activeProjectPlaybackRequest: FusionXProjectPlaybackRequest? = null
    private var activeScrubClipPath: String? = null

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
                onPlaybackCompleted = { handlePlaybackCompleted() },
                reverseScrubPrerollUs = 180_000L,
                resizeRenderTargetOnLoad = false,
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
            activeScrubClipPath = path
            scrubModeActive = false
            val resolvedRequest =
                resolveProjectPlaybackRequestLocked(0L)?.takeIf { it.path == path }
            updateActiveProjectPlaybackRequestLocked(
                resolvedRequest = resolvedRequest,
                emitEvent = resolvedRequest != null,
            )
            activePreviewCoordinator.activatePlayback()
            playbackSession?.loadClip(path)
            generation
        }
    }

    fun syncProject(payload: Map<String, Any?>) {
        synchronized(lock) {
            timelineProjectStore.sync(payload)
            if (timelineProjectStore.projectDurationUs() <= 0L) {
                updateActiveProjectPlaybackRequestLocked(
                    resolvedRequest = null,
                    emitEvent = false,
                )
                activeScrubClipPath = null
                return
            }
            val resolvedRequest = resolveProjectPlaybackRequestLocked(
                transport.currentTimelineTimeUs(),
            )
            if (resolvedRequest != null &&
                activeProjectPlaybackRequest?.path == resolvedRequest.path
            ) {
                updateActiveProjectPlaybackRequestLocked(
                    resolvedRequest = resolvedRequest,
                    emitEvent = false,
                )
            }
        }
    }

    fun currentProjectCanvasSnapshot(): Map<String, Any?> {
        synchronized(lock) {
            return timelineProjectStore.currentCanvasSnapshot()
        }
    }

    fun resolveProjectPlaybackAtTimelineTimeUs(timelineTimeUs: Long): Map<String, Any?> {
        synchronized(lock) {
            return timelineProjectStore.resolvePlaybackAtTimelineTimeUs(timelineTimeUs)
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
        val resolvedRequest: FusionXProjectPlaybackRequest?
        val currentRequest: FusionXProjectPlaybackRequest?
        val currentPlaybackPath: String?
        synchronized(lock) {
            activePlaybackSession =
                playbackSession ?: throw IllegalStateException("Load a clip before scrubbing.")
            activeScrubSession = scrubSession
            resolvedTargetTimelineTimeUs =
                targetTimelineTimeUs
                    ?: lastRequestedScrubTimelineTimeUs
                    ?: transport.currentTimelineTimeUs()
            currentRequest = activeProjectPlaybackRequest
            resolvedRequest = resolveProjectPlaybackRequestLocked(resolvedTargetTimelineTimeUs)
            currentPlaybackPath = activePlaybackSession.currentClipPath()
        }
        activeScrubSession?.stopAndDrain()
        activePlaybackSession.stopAndDrainScrub()
        synchronized(lock) {
            scrubModeActive = false
            lastRequestedScrubTimelineTimeUs = null
            previewCoordinator?.activatePlayback()
        }
        if (resolvedRequest != null &&
            (currentRequest == null ||
                currentRequest.clipId != resolvedRequest.clipId ||
                currentRequest.timelineStartUs != resolvedRequest.timelineStartUs ||
                currentPlaybackPath != resolvedRequest.path)
        ) {
            activateResolvedPlayback(
                resolvedRequest = resolvedRequest,
                autoplay = false,
            )
            return
        }
        if (resolvedRequest != null) {
            activePlaybackSession.activateClipWindow(
                trimStartUs = resolvedRequest.trimStartUs,
                trimEndUs = resolvedRequest.trimEndUs,
                initialClipLocalTimeUs = resolvedRequest.clipLocalTimeUs,
                autoplay = false,
                timelineOffsetUs = resolvedRequest.timelineStartUs,
            )
            return
        }
        activePlaybackSession.seekToTimelineTimeUs(resolvedTargetTimelineTimeUs)
    }

    fun play() {
        val activePlaybackSession: FusionXDecoderSession
        val activeScrubSession: FusionXScrubSession?
        val resolvedRequest: FusionXProjectPlaybackRequest?
        val currentRequest: FusionXProjectPlaybackRequest?
        val currentPlaybackPath: String?
        synchronized(lock) {
            activePlaybackSession =
                playbackSession ?: throw IllegalStateException("Load a clip before playback.")
            activeScrubSession = scrubSession
            currentRequest = activeProjectPlaybackRequest
            resolvedRequest = resolveProjectPlaybackRequestLocked(
                transport.currentTimelineTimeUs(),
            )
            currentPlaybackPath = activePlaybackSession.currentClipPath()
        }
        activeScrubSession?.stopAndDrain()
        activePlaybackSession.stopAndDrainScrub()
        synchronized(lock) {
            scrubModeActive = false
            lastRequestedScrubTimelineTimeUs = null
            previewCoordinator?.activatePlayback()
        }
        if (resolvedRequest != null &&
            (currentRequest == null ||
                currentRequest.clipId != resolvedRequest.clipId ||
                currentRequest.timelineStartUs != resolvedRequest.timelineStartUs ||
                currentPlaybackPath != resolvedRequest.path)
        ) {
            activateResolvedPlayback(
                resolvedRequest = resolvedRequest,
                autoplay = true,
            )
            return
        }
        if (resolvedRequest != null) {
            activePlaybackSession.activateClipWindow(
                trimStartUs = resolvedRequest.trimStartUs,
                trimEndUs = resolvedRequest.trimEndUs,
                initialClipLocalTimeUs = resolvedRequest.clipLocalTimeUs,
                autoplay = true,
                timelineOffsetUs = resolvedRequest.timelineStartUs,
            )
        } else {
            activePlaybackSession.play()
        }
    }

    fun pause() {
        synchronized(lock) {
            playbackSession?.pause()
        }
    }

    fun seekTo(timelineTimeUs: Long) {
        val activePlaybackSession: FusionXDecoderSession
        val activeScrubSession: FusionXScrubSession?
        val resolvedRequest: FusionXProjectPlaybackRequest?
        val currentRequest: FusionXProjectPlaybackRequest?
        val resumePlayback: Boolean
        val currentPlaybackPath: String?
        synchronized(lock) {
            activePlaybackSession =
                playbackSession ?: throw IllegalStateException("Load a clip before seeking.")
            activeScrubSession = scrubSession
            currentRequest = activeProjectPlaybackRequest
            resolvedRequest = resolveProjectPlaybackRequestLocked(timelineTimeUs)
            resumePlayback = transport.currentPlaybackState() == FusionXPlaybackState.PLAYING
            currentPlaybackPath = activePlaybackSession.currentClipPath()
        }
        activeScrubSession?.stopAndDrain()
        activePlaybackSession.stopAndDrainScrub()
        synchronized(lock) {
            scrubModeActive = false
            lastRequestedScrubTimelineTimeUs = null
            previewCoordinator?.activatePlayback()
        }
        if (resolvedRequest == null) {
            activePlaybackSession.seekToTimelineTimeUs(timelineTimeUs)
            return
        }
        if (currentRequest == null ||
            currentRequest.clipId != resolvedRequest.clipId ||
            currentRequest.timelineStartUs != resolvedRequest.timelineStartUs ||
            currentPlaybackPath != resolvedRequest.path
        ) {
            activateResolvedPlayback(
                resolvedRequest = resolvedRequest,
                autoplay = resumePlayback,
            )
            return
        }
        activePlaybackSession.activateClipWindow(
            trimStartUs = resolvedRequest.trimStartUs,
            trimEndUs = resolvedRequest.trimEndUs,
            initialClipLocalTimeUs = resolvedRequest.clipLocalTimeUs,
            autoplay = resumePlayback,
            timelineOffsetUs = resolvedRequest.timelineStartUs,
        )
    }

    fun scrubTo(timelineTimeUs: Long, forceReprepare: Boolean = false) {
        val activeScrubSession: FusionXScrubSession?
        val activePlaybackSession: FusionXDecoderSession?
        val resolvedRequest: FusionXProjectPlaybackRequest?
        val currentRequest: FusionXProjectPlaybackRequest?
        val currentPlaybackPath: String?
        synchronized(lock) {
            playbackSession ?: throw IllegalStateException("Load a clip before scrubbing.")
            if (!scrubModeActive) {
                scrubModeActive = true
            }
            lastRequestedScrubTimelineTimeUs = timelineTimeUs
            activeScrubSession = scrubSession
            activePlaybackSession = playbackSession
            currentRequest = activeProjectPlaybackRequest
            resolvedRequest = resolveProjectPlaybackRequestLocked(timelineTimeUs)
            currentPlaybackPath = activePlaybackSession?.currentClipPath()
        }

        if (resolvedRequest != null &&
            (currentRequest == null ||
                currentRequest.clipId != resolvedRequest.clipId ||
                currentRequest.timelineStartUs != resolvedRequest.timelineStartUs ||
                currentPlaybackPath != resolvedRequest.path)
        ) {
            activeScrubSession?.stopAndDrain()
            activePlaybackSession?.stopAndDrainScrub()
            activateResolvedPlayback(
                resolvedRequest = resolvedRequest,
                autoplay = false,
            )
            return
        }

        val handledByProxy =
            activeScrubSession?.requestScrubAtTimelineTimeUs(
                timelineTimeUs = timelineTimeUs,
                forceReprepare = forceReprepare,
            ) == true
        if (!handledByProxy) {
            activePlaybackSession?.scrubToTimelineTimeUs(
                timelineTimeUs = timelineTimeUs,
                forceReprepare = forceReprepare,
            )
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

    private fun handlePlaybackCompleted(): FusionXPlaybackContinuation? {
        val handoffContext = synchronized(lock) {
            val current = activeProjectPlaybackRequest ?: return@synchronized null
            val nextTimelineStartUs = current.nextTimelineStartUs ?: return@synchronized null
            val nextRequest = resolveProjectPlaybackRequestLocked(nextTimelineStartUs)
                ?: return@synchronized null
            updateActiveProjectPlaybackRequestLocked(
                resolvedRequest = nextRequest.copy(
                    clipLocalTimeUs = 0L,
                    autoplay = true,
                ),
                emitEvent = true,
                syncTransportTimelineOffset = false,
            )
            val scrubReloadRequest = buildScrubReloadRequestLocked(nextRequest.path)
            val continuation = FusionXPlaybackContinuation(
                path = nextRequest.path,
                trimStartUs = nextRequest.trimStartUs,
                trimEndUs = nextRequest.trimEndUs,
                initialClipLocalTimeUs = 0L,
                timelineOffsetUs = nextRequest.timelineStartUs,
            )
            FusionXHandoffContext(
                continuation = continuation,
                scrubReloadRequest = scrubReloadRequest,
            )
        } ?: return null

        handoffContext.scrubReloadRequest?.let { scrubReloadRequest ->
            scrubReloadRequest.session.loadClip(
                path = scrubReloadRequest.path,
                sourceWidth = scrubReloadRequest.width,
                sourceHeight = scrubReloadRequest.height,
            )
            scheduleScrubPreparation(scrubReloadRequest.generation)
        }
        return handoffContext.continuation
    }

    private fun activateResolvedPlayback(
        resolvedRequest: FusionXProjectPlaybackRequest,
        autoplay: Boolean,
    ) {
        val previousPath = synchronized(lock) { playbackSession?.currentClipPath() }
        val activationContext = synchronized(lock) {
            previewCoordinator?.activatePlayback()
            updateActiveProjectPlaybackRequestLocked(
                resolvedRequest = resolvedRequest.copy(autoplay = autoplay),
                emitEvent = true,
                syncTransportTimelineOffset = false,
            )
            val scrubReloadRequest = buildScrubReloadRequestLocked(resolvedRequest.path)
            FusionXActivationContext(
                playbackSession = playbackSession,
                scrubReloadRequest = scrubReloadRequest,
            )
        }
        val activePlaybackSession = activationContext.playbackSession ?: return
        activationContext.scrubReloadRequest?.let { scrubReloadRequest ->
            scrubReloadRequest.session.loadClip(
                path = scrubReloadRequest.path,
                sourceWidth = scrubReloadRequest.width,
                sourceHeight = scrubReloadRequest.height,
            )
            scheduleScrubPreparation(scrubReloadRequest.generation)
        }

        if (previousPath == resolvedRequest.path) {
            activePlaybackSession.activateClipWindow(
                trimStartUs = resolvedRequest.trimStartUs,
                trimEndUs = resolvedRequest.trimEndUs,
                initialClipLocalTimeUs = resolvedRequest.clipLocalTimeUs,
                autoplay = autoplay,
                timelineOffsetUs = resolvedRequest.timelineStartUs,
            )
            return
        }
        activePlaybackSession.loadClipWindow(
            path = resolvedRequest.path,
            trimStartUs = resolvedRequest.trimStartUs,
            trimEndUs = resolvedRequest.trimEndUs,
            initialClipLocalTimeUs = resolvedRequest.clipLocalTimeUs,
            autoplay = autoplay,
            timelineOffsetUs = resolvedRequest.timelineStartUs,
        )
    }

    private fun updateActiveProjectPlaybackRequestLocked(
        resolvedRequest: FusionXProjectPlaybackRequest?,
        emitEvent: Boolean,
        syncTransportTimelineOffset: Boolean = true,
    ) {
        activeProjectPlaybackRequest = resolvedRequest
        if (syncTransportTimelineOffset) {
            transport.setTimelineOffsetUs(resolvedRequest?.timelineStartUs ?: 0L)
        }
        if (emitEvent && resolvedRequest != null) {
            events.emit(
                "activeClipChanged",
                mapOf(
                    "clipId" to resolvedRequest.clipId,
                    "assetId" to resolvedRequest.assetId,
                    "path" to resolvedRequest.path,
                    "timelineStartUs" to resolvedRequest.timelineStartUs,
                    "timelineTimeUs" to resolvedRequest.timelineTimeUs,
                    "clipLocalTimeUs" to resolvedRequest.clipLocalTimeUs,
                    "sourceOffsetUs" to resolvedRequest.sourceOffsetUs,
                ),
            )
        }
    }

    private fun buildScrubReloadRequestLocked(path: String): FusionXScrubReloadRequest? {
        if (activeScrubClipPath == path) {
            return null
        }
        activeScrubClipPath = path
        val activePreviewCoordinator = previewCoordinator ?: return null
        val activeScrubSession = scrubSession ?: return null
        return FusionXScrubReloadRequest(
            session = activeScrubSession,
            path = path,
            width = activePreviewCoordinator.scrubTarget().width,
            height = activePreviewCoordinator.scrubTarget().height,
            generation = clipLoadGeneration,
        )
    }

    private fun resolveProjectPlaybackRequestLocked(
        timelineTimeUs: Long,
    ): FusionXProjectPlaybackRequest? {
        val snapshot = timelineProjectStore.resolvePlaybackAtTimelineTimeUs(timelineTimeUs)
        val hasActiveClip = snapshot["hasActiveClip"] as? Boolean ?: false
        if (!hasActiveClip) {
            return null
        }
        val path = snapshot["activePath"] as? String ?: return null
        val clipId = snapshot["activeClipId"] as? String ?: return null
        return FusionXProjectPlaybackRequest(
            clipId = clipId,
            assetId = snapshot["activeAssetId"] as? String,
            path = path,
            timelineStartUs = (snapshot["activeClipTimelineStartUs"] as? Number)?.toLong() ?: 0L,
            timelineTimeUs = (snapshot["timelineTimeUs"] as? Number)?.toLong() ?: 0L,
            clipLocalTimeUs = (snapshot["activeClipLocalTimeUs"] as? Number)?.toLong() ?: 0L,
            sourceOffsetUs = (snapshot["activeSourceOffsetUs"] as? Number)?.toLong() ?: 0L,
            durationUs = (snapshot["activeClipDurationUs"] as? Number)?.toLong() ?: 0L,
            trimStartUs = (snapshot["activeSourceOffsetUs"] as? Number)?.toLong() ?: 0L,
            trimEndUs = ((snapshot["activeSourceOffsetUs"] as? Number)?.toLong() ?: 0L) +
                ((snapshot["activeClipDurationUs"] as? Number)?.toLong() ?: 0L),
            nextClipId = snapshot["nextClipId"] as? String,
            nextPath = snapshot["nextPath"] as? String,
            nextTimelineStartUs = (snapshot["nextTimelineStartUs"] as? Number)?.toLong(),
            nextSourceOffsetUs = (snapshot["nextSourceOffsetUs"] as? Number)?.toLong(),
            nextDurationUs = (snapshot["nextDurationUs"] as? Number)?.toLong(),
            autoplay = false,
        )
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
        lateinit var prepareRunnable: Runnable
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
        if (SCRUB_PREPARE_DELAY_MS <= 0L) {
            mainHandler.post(prepareRunnable)
        } else {
            mainHandler.postDelayed(prepareRunnable, SCRUB_PREPARE_DELAY_MS)
        }
    }

    private fun detachRenderTargetLocked() {
        pendingScrubPrepareRunnable?.let(mainHandler::removeCallbacks)
        pendingScrubPrepareRunnable = null
        scrubSession?.release()
        scrubSession = null
        activeScrubClipPath = null
        activeProjectPlaybackRequest = null
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

    private data class FusionXProjectPlaybackRequest(
        val clipId: String,
        val assetId: String?,
        val path: String,
        val timelineStartUs: Long,
        val timelineTimeUs: Long,
        val clipLocalTimeUs: Long,
        val sourceOffsetUs: Long,
        val durationUs: Long,
        val trimStartUs: Long,
        val trimEndUs: Long,
        val nextClipId: String?,
        val nextPath: String?,
        val nextTimelineStartUs: Long?,
        val nextSourceOffsetUs: Long?,
        val nextDurationUs: Long?,
        val autoplay: Boolean,
    )

    private data class FusionXActivationContext(
        val playbackSession: FusionXDecoderSession?,
        val scrubReloadRequest: FusionXScrubReloadRequest?,
    )

    private data class FusionXHandoffContext(
        val continuation: FusionXPlaybackContinuation,
        val scrubReloadRequest: FusionXScrubReloadRequest?,
    )

    private data class FusionXScrubReloadRequest(
        val session: FusionXScrubSession,
        val path: String,
        val width: Int,
        val height: Int,
        val generation: Long,
    )
}
