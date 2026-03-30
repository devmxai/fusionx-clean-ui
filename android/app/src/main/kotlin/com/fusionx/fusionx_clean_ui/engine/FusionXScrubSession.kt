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
    private var proxyAsset: FusionXProxyAsset? = null
    private var proxySession: FusionXDecoderSession? = null
    private var proxyPreparing = false
    private var proxySessionPrepared = false
    private var requestGeneration = 0L

    fun loadClip(
        path: String,
        sourceWidth: Int,
        sourceHeight: Int,
    ) {
        val generation = synchronized(lock) {
            requestGeneration += 1L
            sourceClipPath = path
            proxyAsset = null
            proxyPreparing = true
            proxySessionPrepared = false
            proxySession?.release()
            proxySession = null
            requestGeneration
        }
        proxyConformer.cancel()
        proxyConformer.prepareProxy(
            sourcePath = path,
            sourceWidth = sourceWidth,
            sourceHeight = sourceHeight,
            onReady = { asset ->
                val nextSession = FusionXDecoderSession(
                    applicationContext = applicationContext,
                    renderTarget = renderTarget,
                    transport = transport,
                    events = events,
                    announceClipLoaded = false,
                    onClipPrepared = {
                        synchronized(lock) {
                            if (requestGeneration == generation &&
                                proxyAsset?.path == asset.path
                            ) {
                                proxySessionPrepared = true
                            }
                        }
                    },
                    renderInitialFrameOnLoad = false,
                )
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
        val activeProxySession = synchronized(lock) {
            if (!proxySessionPrepared) {
                null
            } else {
                proxySession
            }
        } ?: return false
        activeProxySession.scrubToTimelineTimeUs(timelineTimeUs)
        return true
    }

    fun stopAndDrain(timeoutMs: Long = 250L) {
        proxySession?.stopAndDrainScrub(timeoutMs)
    }

    fun release() {
        proxyConformer.cancel()
        synchronized(lock) {
            requestGeneration += 1L
            sourceClipPath = null
            proxyAsset = null
            proxyPreparing = false
            proxySessionPrepared = false
            proxySession?.release()
            proxySession = null
        }
    }
}
