package com.fusionx.fusionx_clean_ui.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.Surface
import io.flutter.view.TextureRegistry

class FusionXRenderTarget(
    textureRegistry: TextureRegistry,
    width: Int,
    height: Int,
) {
    private val surfaceTextureEntry = textureRegistry.createSurfaceTexture()
    private val surfaceTexture = surfaceTextureEntry.surfaceTexture()
    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val drawRect = RectF()
    private val lock = Any()

    val surface: Surface = Surface(surfaceTexture)
    val textureId: Long = surfaceTextureEntry.id()
    var width: Int = width
        private set
    var height: Int = height
        private set

    init {
        resize(width, height)
    }

    fun resize(width: Int, height: Int) {
        val safeWidth = width.coerceAtLeast(1)
        val safeHeight = height.coerceAtLeast(1)
        this.width = safeWidth
        this.height = safeHeight
        surfaceTexture.setDefaultBufferSize(safeWidth, safeHeight)
    }

    fun drawBitmap(bitmap: Bitmap) {
        synchronized(lock) {
            val canvas = try {
                surface.lockCanvas(null)
            } catch (_: Throwable) {
                return
            }

            try {
                drawBitmapToCanvas(canvas, bitmap)
            } finally {
                surface.unlockCanvasAndPost(canvas)
            }
        }
    }

    fun currentFrameSequence(): Long = 0L

    fun awaitNextFrame(previousFrameSequence: Long, timeoutMs: Long): Boolean = true

    private fun drawBitmapToCanvas(canvas: Canvas, bitmap: Bitmap) {
        val targetWidth = width.toFloat().coerceAtLeast(1f)
        val targetHeight = height.toFloat().coerceAtLeast(1f)
        val bitmapWidth = bitmap.width.toFloat().coerceAtLeast(1f)
        val bitmapHeight = bitmap.height.toFloat().coerceAtLeast(1f)
        val scale = minOf(targetWidth / bitmapWidth, targetHeight / bitmapHeight)
        val scaledWidth = bitmapWidth * scale
        val scaledHeight = bitmapHeight * scale
        val left = (targetWidth - scaledWidth) / 2f
        val top = (targetHeight - scaledHeight) / 2f

        canvas.drawColor(Color.BLACK)
        drawRect.set(left, top, left + scaledWidth, top + scaledHeight)
        canvas.drawBitmap(bitmap, null, drawRect, bitmapPaint)
    }

    fun release() {
        surface.release()
        surfaceTextureEntry.release()
    }
}
