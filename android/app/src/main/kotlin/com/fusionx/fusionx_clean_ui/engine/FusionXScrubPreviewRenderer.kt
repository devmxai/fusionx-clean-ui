package com.fusionx.fusionx_clean_ui.engine

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future

class FusionXScrubPreviewRenderer(
    private val applicationContext: Context,
    private val renderTarget: FusionXRenderTarget,
    private val transport: FusionXTransport,
    private val events: FusionXEventDispatcher,
) {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val lock = Any()

    private var retriever: MediaMetadataRetriever? = null
    private var activeTask: Future<*>? = null
    private var workerScheduled = false
    private var pendingSourceTimeUs: Long? = null
    private var generation = 0L

    fun loadClip(path: String) {
        clearPending()
        releaseRetriever()

        val nextRetriever = MediaMetadataRetriever()
        if (path.startsWith("content://") || path.startsWith("file://")) {
            nextRetriever.setDataSource(applicationContext, Uri.parse(path))
        } else {
            nextRetriever.setDataSource(path)
        }

        synchronized(lock) {
            retriever = nextRetriever
        }
    }

    fun requestFrame(sourceTimeUs: Long) {
        val requestGeneration: Long
        synchronized(lock) {
            pendingSourceTimeUs = sourceTimeUs.coerceAtLeast(0L)
            requestGeneration = generation
            if (workerScheduled) {
                return
            }
            workerScheduled = true
        }

        activeTask = executor.submit {
            try {
                renderLoop(requestGeneration)
            } finally {
                val shouldRestart = synchronized(lock) {
                    workerScheduled = false
                    pendingSourceTimeUs != null
                }
                if (shouldRestart && !executor.isShutdown) {
                    requestFrame(
                        synchronized(lock) {
                            pendingSourceTimeUs ?: 0L
                        },
                    )
                }
            }
        }
    }

    fun cancelPending() {
        clearPending()
        activeTask?.cancel(true)
        activeTask = null
    }

    fun release() {
        cancelPending()
        releaseRetriever()
        executor.shutdownNow()
    }

    private fun renderLoop(requestGeneration: Long) {
        while (!Thread.currentThread().isInterrupted) {
            val sourceTimeUs = synchronized(lock) {
                val next = pendingSourceTimeUs
                pendingSourceTimeUs = null
                next
            } ?: return

            val bitmap = extractBitmap(sourceTimeUs) ?: continue
            if (isRequestInvalidated(requestGeneration) || hasPendingRequest()) {
                bitmap.recycle()
                continue
            }

            renderTarget.drawBitmap(bitmap)
            transport.setSourcePositionUs(sourceTimeUs)
            val encodedBytes = encodeBitmap(bitmap)
            if (encodedBytes != null && !isRequestInvalidated(requestGeneration)) {
                events.emit(
                    "scrubFrameAvailable",
                    mapOf(
                        "sourceTimeUs" to sourceTimeUs,
                        "frameBytes" to encodedBytes,
                    ),
                )
            }
            bitmap.recycle()
        }
    }

    private fun extractBitmap(sourceTimeUs: Long): Bitmap? {
        val activeRetriever = synchronized(lock) { retriever } ?: return null
        val targetSize = computeTargetSize()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activeRetriever.getScaledFrameAtTime(
                sourceTimeUs,
                MediaMetadataRetriever.OPTION_CLOSEST,
                targetSize.first,
                targetSize.second,
            )
        } else {
            val rawBitmap = activeRetriever.getFrameAtTime(
                sourceTimeUs,
                MediaMetadataRetriever.OPTION_CLOSEST,
            ) ?: return null
            if (rawBitmap.width == targetSize.first && rawBitmap.height == targetSize.second) {
                rawBitmap
            } else {
                Bitmap.createScaledBitmap(
                    rawBitmap,
                    targetSize.first,
                    targetSize.second,
                    true,
                ).also {
                    if (it != rawBitmap) {
                        rawBitmap.recycle()
                    }
                }
            }
        }
    }

    private fun computeTargetSize(): Pair<Int, Int> {
        val targetWidth = renderTarget.width.coerceAtLeast(1)
        val targetHeight = renderTarget.height.coerceAtLeast(1)
        val maxEdge = maxOf(targetWidth, targetHeight).coerceAtLeast(1)
        val scale = if (maxEdge > 480) {
            480f / maxEdge.toFloat()
        } else {
            1f
        }
        return Pair(
            (targetWidth * scale).toInt().coerceAtLeast(1),
            (targetHeight * scale).toInt().coerceAtLeast(1),
        )
    }

    private fun encodeBitmap(bitmap: Bitmap): ByteArray? {
        return ByteArrayOutputStream().use { outputStream ->
            val encoded = bitmap.compress(Bitmap.CompressFormat.JPEG, 72, outputStream)
            if (!encoded) {
                return null
            }
            outputStream.toByteArray()
        }
    }

    private fun hasPendingRequest(): Boolean {
        synchronized(lock) {
            return pendingSourceTimeUs != null
        }
    }

    private fun clearPending() {
        synchronized(lock) {
            generation += 1L
            pendingSourceTimeUs = null
            workerScheduled = false
        }
    }

    private fun isRequestInvalidated(requestGeneration: Long): Boolean {
        synchronized(lock) {
            return generation != requestGeneration
        }
    }

    private fun releaseRetriever() {
        synchronized(lock) {
            try {
                retriever?.release()
            } catch (_: Throwable) {
            }
            retriever = null
        }
    }
}
