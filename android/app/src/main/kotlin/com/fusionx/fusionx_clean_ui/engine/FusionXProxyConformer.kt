package com.fusionx.fusionx_clean_ui.engine

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.TransformationRequest
import androidx.media3.transformer.Transformer
import java.io.File
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.min

class FusionXProxyConformer(
    private val applicationContext: Context,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    private var requestGeneration = 0L
    private var activeTransformer: Transformer? = null

    fun prepareProxy(
        sourcePath: String,
        sourceWidth: Int,
        sourceHeight: Int,
        onReady: (FusionXProxyAsset) -> Unit,
        onFailure: (Throwable) -> Unit,
    ) {
        val proxyShortSide = resolveProxyShortSide(sourceWidth, sourceHeight)
        val proxyFile = resolveProxyFile(sourcePath, proxyShortSide)
        if (proxyFile.exists() && proxyFile.length() > 0L) {
            onReady(
                FusionXProxyAsset(
                    path = proxyFile.absolutePath,
                    shortSide = proxyShortSide,
                ),
            )
            return
        }

        val tempFile = File(proxyFile.absolutePath + ".tmp")
        tempFile.parentFile?.mkdirs()
        if (tempFile.exists()) {
            tempFile.delete()
        }

        val generation = synchronized(lock) {
            requestGeneration += 1L
            requestGeneration
        }

        mainHandler.post {
            synchronized(lock) {
                activeTransformer?.cancel()
                activeTransformer = null
            }

            val (proxyWidth, proxyHeight) = resolveProxySize(sourceWidth, sourceHeight, proxyShortSide)
            val presentation = Presentation.createForWidthAndHeight(
                proxyWidth,
                proxyHeight,
                Presentation.LAYOUT_SCALE_TO_FIT,
            )
            val mediaItem = MediaItem.fromUri(resolveMediaUri(sourcePath))
            val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                .setRemoveAudio(true)
                .setEffects(
                    Effects(
                        emptyList(),
                        listOf(presentation),
                    ),
                )
                .build()

            val transformationRequest = TransformationRequest.Builder()
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .build()
            val transformer = Transformer.Builder(applicationContext)
                .setTransformationRequest(transformationRequest)
                .addListener(
                    object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult,
                        ) {
                            if (!isCurrentGeneration(generation)) {
                                tempFile.delete()
                                return
                            }
                            tempFile.parentFile?.mkdirs()
                            if (proxyFile.exists()) {
                                proxyFile.delete()
                            }
                            if (!tempFile.renameTo(proxyFile)) {
                                tempFile.copyTo(proxyFile, overwrite = true)
                                tempFile.delete()
                            }
                            synchronized(lock) {
                                if (requestGeneration == generation) {
                                    activeTransformer = null
                                }
                            }
                            onReady(
                                FusionXProxyAsset(
                                    path = proxyFile.absolutePath,
                                    shortSide = proxyShortSide,
                                ),
                            )
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException,
                        ) {
                            if (!isCurrentGeneration(generation)) {
                                tempFile.delete()
                                return
                            }
                            synchronized(lock) {
                                if (requestGeneration == generation) {
                                    activeTransformer = null
                                }
                            }
                            tempFile.delete()
                            onFailure(exportException)
                        }
                    },
                )
                .build()

            synchronized(lock) {
                if (requestGeneration != generation) {
                    return@post
                }
                activeTransformer = transformer
            }
            transformer.start(editedMediaItem, tempFile.absolutePath)
        }
    }

    fun cancel() {
        val generation = synchronized(lock) {
            requestGeneration += 1L
            requestGeneration
        }
        mainHandler.post {
            synchronized(lock) {
                if (requestGeneration == generation) {
                    activeTransformer?.cancel()
                    activeTransformer = null
                } else {
                    activeTransformer?.cancel()
                    activeTransformer = null
                }
            }
        }
    }

    private fun isCurrentGeneration(generation: Long): Boolean {
        synchronized(lock) {
            return requestGeneration == generation
        }
    }

    private fun resolveMediaUri(sourcePath: String): Uri {
        return when {
            sourcePath.startsWith("content://") || sourcePath.startsWith("file://") ->
                Uri.parse(sourcePath)
            else -> Uri.fromFile(File(sourcePath))
        }
    }

    private fun resolveProxyFile(sourcePath: String, shortSide: Int): File {
        val cacheDirectory = File(applicationContext.cacheDir, "fusionx_proxy")
        cacheDirectory.mkdirs()
        val cacheKey = sha256("$PROXY_SCHEMA_VERSION|$sourcePath|$shortSide").take(24)
        return File(cacheDirectory, "proxy_$cacheKey.mp4")
    }

    private fun resolveProxyShortSide(width: Int, height: Int): Int {
        val sourceShortSide = min(width.coerceAtLeast(1), height.coerceAtLeast(1))
        return max(MIN_PROXY_SHORT_SIDE, min(MAX_PROXY_SHORT_SIDE, sourceShortSide))
    }

    private fun resolveProxySize(width: Int, height: Int, shortSide: Int): Pair<Int, Int> {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        val sourceShortSide = min(safeWidth, safeHeight).coerceAtLeast(1)
        val scale = shortSide.toFloat() / sourceShortSide.toFloat()
        val targetWidth = max(1, (safeWidth * scale).toInt())
        val targetHeight = max(1, (safeHeight * scale).toInt())
        return targetWidth to targetHeight
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return buildString(digest.size * 2) {
            for (byte in digest) {
                append("%02x".format(byte))
            }
        }
    }

    companion object {
        private const val MIN_PROXY_SHORT_SIDE = 540
        private const val MAX_PROXY_SHORT_SIDE = 720
        private const val PROXY_SCHEMA_VERSION = "proxy_v1"
    }
}
