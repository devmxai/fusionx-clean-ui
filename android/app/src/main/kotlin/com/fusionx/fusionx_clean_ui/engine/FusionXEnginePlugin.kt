package com.fusionx.fusionx_clean_ui.engine

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class FusionXEnginePlugin(
    messenger: BinaryMessenger,
    applicationContext: Context,
    textureRegistry: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val vulkanBridge = FusionXVulkanBridge()
    private val controller = FusionXEngineController(
        applicationContext = applicationContext,
        textureRegistry = textureRegistry,
        events = object : FusionXEventDispatcher {
            override fun emit(type: String, payload: Map<String, Any?>) {
                emitEvent(type, payload)
            }
        },
    )

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)

    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "attachRenderTarget" -> {
                    val width = (call.argument<Number>("width")?.toInt() ?: 720)
                    val height = (call.argument<Number>("height")?.toInt() ?: 1280)
                    val textureId = controller.attachRenderTarget(width, height)
                    result.success(mapOf("textureId" to textureId))
                }

                "detachRenderTarget" -> {
                    controller.detachRenderTarget()
                    result.success(null)
                }

                "loadClip" -> {
                    val path = call.argument<String>("path")
                        ?: throw IllegalArgumentException("Missing local clip path.")
                    controller.loadClip(path)
                    result.success(null)
                }

                "beginScrub" -> {
                    controller.beginScrub()
                    result.success(null)
                }

                "endScrub" -> {
                    val timelineTimeUs = call.argument<Number>("timelineTimeUs")?.toLong()
                    controller.endScrub(timelineTimeUs)
                    result.success(null)
                }

                "play" -> {
                    controller.play()
                    result.success(null)
                }

                "pause" -> {
                    controller.pause()
                    result.success(null)
                }

                "seekTo" -> {
                    val timelineTimeUs = call.argument<Number>("timelineTimeUs")?.toLong()
                        ?: throw IllegalArgumentException("Missing timelineTimeUs.")
                    controller.seekTo(timelineTimeUs)
                    result.success(null)
                }

                "scrubTo" -> {
                    val timelineTimeUs = call.argument<Number>("timelineTimeUs")?.toLong()
                        ?: throw IllegalArgumentException("Missing timelineTimeUs.")
                    controller.scrubTo(timelineTimeUs)
                    result.success(null)
                }

                "setTrim" -> {
                    val trimStartUs = call.argument<Number>("trimStartUs")?.toLong()
                        ?: throw IllegalArgumentException("Missing trimStartUs.")
                    val trimEndUs = call.argument<Number>("trimEndUs")?.toLong()
                        ?: throw IllegalArgumentException("Missing trimEndUs.")
                    controller.setTrim(trimStartUs, trimEndUs)
                    result.success(null)
                }

                "dispose" -> {
                    controller.dispose()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (throwable: Throwable) {
            emitEvent(
                type = "error",
                payload = mapOf("message" to (throwable.message ?: "Unknown engine error.")),
            )
            result.error("fusionx_engine_error", throwable.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val vulkanCapabilities = vulkanBridge.queryCapabilities()
        emitEvent(
            type = "ready",
            payload = mapOf(
                "phase" to "vulkan_phase0_bootstrap",
                "legacyPlaybackFoundationActive" to true,
                "targetRenderer" to "android_vulkan",
                "vulkan" to vulkanCapabilities.toMap(),
            ),
        )
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emitEvent(type: String, payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to type,
                    "payload" to payload,
                ),
            )
        }
    }

    companion object {
        private const val METHOD_CHANNEL_NAME = "fusionx.engine/methods"
        private const val EVENT_CHANNEL_NAME = "fusionx.engine/events"
    }
}
