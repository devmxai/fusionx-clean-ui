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

    private var renderTarget: FusionXRenderTarget? = null
    private var decoderSession: FusionXDecoderSession? = null

    fun attachRenderTarget(width: Int, height: Int): Long {
        synchronized(lock) {
            detachRenderTargetLocked()
            val nextTarget = FusionXRenderTarget(textureRegistry, width, height)
            renderTarget = nextTarget
            transport.emitReady(
                mapOf(
                    "textureId" to nextTarget.textureId,
                    "renderTargetAttached" to true,
                ),
            )
            return nextTarget.textureId
        }
    }

    fun detachRenderTarget() {
        synchronized(lock) {
            detachRenderTargetLocked()
        }
    }

    fun loadClip(path: String) {
        val activeRenderTarget = synchronized(lock) {
            renderTarget ?: throw IllegalStateException("Attach a render target before loading a clip.")
        }

        synchronized(lock) {
            decoderSession?.release()
            decoderSession = FusionXDecoderSession(
                applicationContext = applicationContext,
                renderTarget = activeRenderTarget,
                transport = transport,
                events = events,
            )
            decoderSession?.loadClip(path)
        }
    }

    fun play() {
        synchronized(lock) {
            decoderSession ?: throw IllegalStateException("Load a clip before playback.")
            decoderSession?.play()
        }
    }

    fun pause() {
        synchronized(lock) {
            decoderSession?.pause()
        }
    }

    fun seekTo(timelineTimeUs: Long) {
        synchronized(lock) {
            decoderSession ?: throw IllegalStateException("Load a clip before seeking.")
            decoderSession?.seekToTimelineTimeUs(timelineTimeUs)
        }
    }

    fun scrubTo(timelineTimeUs: Long) {
        synchronized(lock) {
            decoderSession ?: throw IllegalStateException("Load a clip before scrubbing.")
            decoderSession?.scrubToTimelineTimeUs(timelineTimeUs)
        }
    }

    fun setTrim(trimStartUs: Long, trimEndUs: Long) {
        synchronized(lock) {
            decoderSession ?: throw IllegalStateException("Load a clip before trimming.")
            decoderSession?.setTrim(trimStartUs, trimEndUs)
        }
    }

    fun dispose() {
        synchronized(lock) {
            decoderSession?.release()
            decoderSession = null
            detachRenderTargetLocked()
        }
    }

    private fun detachRenderTargetLocked() {
        decoderSession?.release()
        decoderSession = null
        renderTarget?.release()
        renderTarget = null
    }
}
