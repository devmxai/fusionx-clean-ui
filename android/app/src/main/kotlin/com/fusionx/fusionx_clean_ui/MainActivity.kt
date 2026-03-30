package com.fusionx.fusionx_clean_ui

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.fusionx.fusionx_clean_ui.engine.FusionXEnginePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var fusionXEnginePlugin: FusionXEnginePlugin? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingMediaQueryResult: MethodChannel.Result? = null
    private var pendingMediaQueryTab: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mediaExecutor = Executors.newFixedThreadPool(3)
    private val mediaCache = mutableMapOf<String, List<Map<String, Any?>>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fusionXEnginePlugin = FusionXEnginePlugin(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            applicationContext = applicationContext,
            textureRegistry = flutterEngine.renderer,
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEBUG_PICKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickVideoClip" -> {
                    if (pendingPickerResult != null) {
                        result.error(
                            "picker_busy",
                            "A clip picker request is already active.",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    pendingPickerResult = result
                    launchVideoPicker()
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_LIBRARY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasMediaPermission" -> {
                    val tab = call.argument<String>("tab")
                        ?: run {
                            result.error("missing_tab", "Missing media tab.", null)
                            return@setMethodCallHandler
                        }
                    result.success(hasMediaPermissions(tab))
                }

                "listDeviceMedia" -> {
                    val tab = call.argument<String>("tab")
                        ?: run {
                            result.error("missing_tab", "Missing media tab.", null)
                            return@setMethodCallHandler
                        }
                    handleDeviceMediaQuery(tab, result)
                }

                "loadMediaThumbnail" -> {
                    val uri = call.argument<String>("uri")
                        ?: run {
                            result.error("missing_uri", "Missing media uri.", null)
                            return@setMethodCallHandler
                        }
                    val targetWidth = call.argument<Number>("targetWidth")?.toInt() ?: 240
                    val targetHeight = call.argument<Number>("targetHeight")?.toInt() ?: 240
                    mediaExecutor.execute {
                        try {
                            val thumbnailBytes = loadMediaThumbnail(
                                uriString = uri,
                                targetWidth = targetWidth,
                                targetHeight = targetHeight,
                            )
                            mainHandler.post {
                                result.success(thumbnailBytes)
                            }
                        } catch (throwable: Throwable) {
                            mainHandler.post {
                                result.error(
                                    "thumbnail_failed",
                                    throwable.message ?: "Unable to load media thumbnail.",
                                    null,
                                )
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VIDEO_PICKER_REQUEST_CODE) {
            return
        }

        val result = pendingPickerResult
        pendingPickerResult = null
        if (result == null) {
            return
        }

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri: Uri? = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
        }

        result.success(uri.toString())
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MEDIA_PERMISSION_REQUEST_CODE) {
            return
        }

        val result = pendingMediaQueryResult
        val tab = pendingMediaQueryTab
        pendingMediaQueryResult = null
        pendingMediaQueryTab = null
        if (result == null || tab == null) {
            return
        }

        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (!granted) {
            result.error(
                "media_permission_denied",
                "Media access was denied. Allow access to show device videos and images.",
                null,
            )
            return
        }

        executeDeviceMediaQuery(tab, result)
    }

    private fun handleDeviceMediaQuery(tab: String, result: MethodChannel.Result) {
        if (pendingMediaQueryResult != null) {
            result.error(
                "media_query_busy",
                "Another media query request is already active.",
                null,
            )
            return
        }

        if (hasMediaPermissions(tab)) {
            val cachedItems = synchronized(mediaCache) { mediaCache[tab] }
            if (cachedItems != null) {
                result.success(cachedItems)
                return
            }
            executeDeviceMediaQuery(tab, result)
            return
        }

        pendingMediaQueryResult = result
        pendingMediaQueryTab = tab
        requestMediaPermissions(tab)
    }

    private fun permissionsForTab(tab: String): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        return when (tab) {
            "image" -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
            else -> arrayOf(Manifest.permission.READ_MEDIA_VIDEO)
        }
    }

    private fun hasMediaPermissions(tab: String): Boolean {
        return permissionsForTab(tab).all { permission ->
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestMediaPermissions(tab: String) {
        ActivityCompat.requestPermissions(
            this,
            permissionsForTab(tab),
            MEDIA_PERMISSION_REQUEST_CODE,
        )
    }

    private fun executeDeviceMediaQuery(tab: String, result: MethodChannel.Result) {
        mediaExecutor.execute {
            try {
                val mediaItems = queryDeviceMedia(tab)
                synchronized(mediaCache) {
                    mediaCache[tab] = mediaItems
                }
                mainHandler.post {
                    result.success(mediaItems)
                }
            } catch (throwable: Throwable) {
                mainHandler.post {
                    result.error(
                        "media_query_failed",
                        throwable.message ?: "Unable to read the Android media library.",
                        null,
                    )
                }
            } finally {
                mainHandler.post {
                    pendingMediaQueryResult = null
                    pendingMediaQueryTab = null
                }
            }
        }
    }

    private fun queryDeviceMedia(tab: String): List<Map<String, Any?>> {
        val isVideo = tab == "video"
        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
        ).apply {
            if (isVideo) {
                add(MediaStore.Video.VideoColumns.DURATION)
            }
        }

        val mediaItems = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            collection,
            projection.toTypedArray(),
            null,
            null,
            "${MediaStore.MediaColumns.DATE_ADDED} DESC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val displayNameIndex =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val mimeTypeIndex =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val widthIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.WIDTH)
            val heightIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.HEIGHT)
            val durationIndex = if (isVideo) {
                cursor.getColumnIndexOrThrow(MediaStore.Video.VideoColumns.DURATION)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val mediaId = cursor.getLong(idIndex)
                val uri = ContentUris.withAppendedId(collection, mediaId)
                val label = cursor.getString(displayNameIndex)
                    ?.takeIf { it.isNotBlank() }
                    ?: if (isVideo) "Video $mediaId" else "Image $mediaId"
                val mimeType = cursor.getString(mimeTypeIndex)
                val width = cursor.getInt(widthIndex).takeIf { it > 0 }
                val height = cursor.getInt(heightIndex).takeIf { it > 0 }
                val durationUs = if (isVideo && durationIndex >= 0) {
                    cursor.getLong(durationIndex) * 1000L
                } else {
                    null
                }

                mediaItems.add(
                    mapOf(
                        "id" to "$tab-$mediaId",
                        "tab" to tab,
                        "uri" to uri.toString(),
                        "label" to label,
                        "mimeType" to mimeType,
                        "width" to width,
                        "height" to height,
                        "durationUs" to durationUs,
                    ),
                )
            }
        }

        return mediaItems
    }

    private fun loadMediaThumbnail(
        uriString: String,
        targetWidth: Int,
        targetHeight: Int,
    ): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return null
        }

        val bitmap = contentResolver.loadThumbnail(
            Uri.parse(uriString),
            Size(
                targetWidth.coerceAtLeast(64),
                targetHeight.coerceAtLeast(64),
            ),
            null,
        )

        return ByteArrayOutputStream().use { outputStream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 82, outputStream)
            outputStream.toByteArray()
        }
    }

    private fun launchVideoPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, VIDEO_PICKER_REQUEST_CODE)
    }

    override fun onDestroy() {
        mediaExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val DEBUG_PICKER_CHANNEL = "fusionx.debug/picker"
        private const val MEDIA_LIBRARY_CHANNEL = "fusionx.media/library"
        private const val VIDEO_PICKER_REQUEST_CODE = 2041
        private const val MEDIA_PERMISSION_REQUEST_CODE = 2042
    }
}
