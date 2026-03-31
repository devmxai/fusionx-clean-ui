package com.fusionx.fusionx_clean_ui.engine

import android.content.Context

class FusionXScrubSession(
    private val applicationContext: Context,
    private val renderTarget: FusionXRenderTarget,
    private val transport: FusionXTransport,
    private val events: FusionXEventDispatcher,
) {
    private val lock = Any()
    private val proxyConformer = FusionXProxyConformer(applicationContext)

    private var sourceClipPath: String? = null
    private var sourceWidth = 0
    private var sourceHeight = 0
    private var proxyAsset: FusionXProxyAsset? = null
    private var proxySession: FusionXDecoderSession? = null
    private var proxyPreparing = false
    private var proxySessionPrepared = false
    private var requestGeneration = 0L
    private var pendingTimelineTimeUs: Long? = null

    fun loadClip(
        path: String,
        sourceWidth: Int,
        sourceHeight: Int,
    ) {
        synchronized(lock) {
            requestGeneration += 1L
            sourceClipPath = path
            this.sourceWidth = sourceWidth
            this.sourceHeight = sourceHeight
            proxyAsset = null
            proxyPreparing = false
            proxySessionPrepared = false
            pendingTimelineTimeUs = null
            proxySession?.release()
            proxySession = null
        }
        proxyConformer.cancel()
    }

    fun prepareProxyIfNeeded() {
        val requestState = synchronized(lock) {
            val shouldStartPreparing =
                !proxyPreparing &&
                    proxyAsset == null &&
                    sourceClipPath != null &&
                    sourceWidth > 0 &&
                    sourceHeight > 0
            if (shouldStartPreparing) {
                proxyPreparing = true
            }
            ProxyRequestState(
                session = proxySession,
                prepared = proxySessionPrepared,
                shouldStartPreparing = shouldStartPreparing,
                generation = requestGeneration,
                clipPath = sourceClipPath,
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
            )
        }

        if (requestState.shouldStartPreparing &&
            requestState.clipPath != null &&
            requestState.sourceWidth > 0 &&
            requestState.sourceHeight > 0
        ) {
            startPreparingProxy(
                generation = requestState.generation,
                path = requestState.clipPath,
                sourceWidth = requestState.sourceWidth,
                sourceHeight = requestState.sourceHeight,
            )
        }
    }

    fun isReady(): Boolean {
        synchronized(lock) {
            return proxyAsset != null && proxySessionPrepared && proxySession != null
        }
    }

    fun isPreparing(): Boolean {
        synchronized(lock) {
            return proxyPreparing
        }
    }

    fun requestScrubAtTimelineTimeUs(timelineTimeUs: Long): Boolean {
        val state = synchronized(lock) {
            pendingTimelineTimeUs = timelineTimeUs
            val shouldStartPreparing =
                !proxyPreparing &&
                    proxyAsset == null &&
                    sourceClipPath != null &&
                    sourceWidth > 0 &&
                    sourceHeight > 0
            if (shouldStartPreparing) {
                proxyPreparing = true
            }
            ProxyRequestState(
                session = proxySession,
                prepared = proxySessionPrepared,
                shouldStartPreparing = shouldStartPreparing,
                generation = requestGeneration,
                clipPath = sourceClipPath,
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
            )
        }

        if (state.prepared) {
            state.session?.scrubToTimelineTimeUs(timelineTimeUs)
            return true
        }

        if (state.shouldStartPreparing &&
            state.clipPath != null &&
            state.sourceWidth > 0 &&
            state.sourceHeight > 0
        ) {
            startPreparingProxy(
                generation = state.generation,
                path = state.clipPath,
                sourceWidth = state.sourceWidth,
                sourceHeight = state.sourceHeight,
            )
        }
        return false
    }

    fun stopAndDrain(timeoutMs: Long = 250L) {
        proxySession?.stopAndDrainScrub(timeoutMs)
    }

    fun release() {
        proxyConformer.cancel()
        synchronized(lock) {
            requestGeneration += 1L
            sourceClipPath = null
            sourceWidth = 0
            sourceHeight = 0
            proxyAsset = null
            proxyPreparing = false
            proxySessionPrepared = false
            pendingTimelineTimeUs = null
            proxySession?.release()
            proxySession = null
        }
    }

    private fun startPreparingProxy(
        generation: Long,
        path: String,
        sourceWidth: Int,
        sourceHeight: Int,
    ) {
        proxyConformer.cancel()
        proxyConformer.prepareProxy(
            sourcePath = path,
            sourceWidth = sourceWidth,
            sourceHeight = sourceHeight,
            onReady = { asset ->
                var sessionForReplay: FusionXDecoderSession? = null
                val nextSession = FusionXDecoderSession(
                    applicationContext = applicationContext,
                    renderTarget = renderTarget,
                    transport = transport,
                    events = events,
                    timeMapper = resolveTimeMapper(asset),
                    announceClipLoaded = false,
                    onClipPrepared = {
                        var pendingTimelineTimeUsToReplay: Long? = null
                        synchronized(lock) {
                            if (requestGeneration == generation &&
                                proxyAsset?.path == asset.path
                            ) {
                                proxySessionPrepared = true
                                pendingTimelineTimeUsToReplay = pendingTimelineTimeUs
                            }
                        }
                        pendingTimelineTimeUsToReplay?.let { timelineTimeUs ->
                            sessionForReplay?.scrubToTimelineTimeUs(timelineTimeUs)
                        }
                    },
                    renderInitialFrameOnLoad = false,
                    resizeRenderTargetOnLoad = false,
                    scrubForwardContinuationWindowUs = PROXY_SCRUB_FORWARD_CONTINUATION_WINDOW_US,
                    scrubProgressiveTargetWindowUs = PROXY_SCRUB_PROGRESSIVE_TARGET_WINDOW_US,
                )
                sessionForReplay = nextSession
                val shouldDiscard = synchronized(lock) {
                    requestGeneration != generation || sourceClipPath != path
                }
                if (shouldDiscard) {
                    nextSession.release()
                } else {
                    synchronized(lock) {
                        proxyAsset = asset
                        proxyPreparing = false
                        proxySessionPrepared = false
                        proxySession?.release()
                        proxySession = nextSession
                    }
                    nextSession.loadClip(asset.path)
                }
            },
            onFailure = {
                synchronized(lock) {
                    if (requestGeneration == generation) {
                        proxyPreparing = false
                        proxyAsset = null
                        proxySessionPrepared = false
                        proxySession?.release()
                        proxySession = null
                    }
                }
            },
        )
    }

    private fun resolveTimeMapper(asset: FusionXProxyAsset): FusionXMediaTimeMapper {
        val sourceDurationUs = asset.sourceDurationUs
        val proxyDurationUs = asset.proxyDurationUs
        if (sourceDurationUs <= 0L || proxyDurationUs <= 0L) {
            return FusionXMediaTimeMapper.Identity
        }
        return FusionXMediaTimeMapper.DurationRatio(
            sourceDurationUs = sourceDurationUs,
            mediaDurationUs = proxyDurationUs,
        )
    }

    private data class ProxyRequestState(
        val session: FusionXDecoderSession?,
        val prepared: Boolean,
        val shouldStartPreparing: Boolean,
        val generation: Long,
        val clipPath: String?,
        val sourceWidth: Int,
        val sourceHeight: Int,
    )

    companion object {
        private const val PROXY_SCRUB_FORWARD_CONTINUATION_WINDOW_US = 1_500_000L
        private const val PROXY_SCRUB_PROGRESSIVE_TARGET_WINDOW_US = 900_000L
    }
}
