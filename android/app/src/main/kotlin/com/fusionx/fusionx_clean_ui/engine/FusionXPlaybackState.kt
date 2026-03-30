package com.fusionx.fusionx_clean_ui.engine

enum class FusionXPlaybackState {
    IDLE,
    READY,
    PLAYING,
    PAUSED,
    SEEKING,
    COMPLETED,
    ERROR;

    fun wireName(): String = name.lowercase()
}
