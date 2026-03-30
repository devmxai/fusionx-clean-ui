package com.fusionx.fusionx_clean_ui.engine

interface FusionXEventDispatcher {
    fun emit(type: String, payload: Map<String, Any?> = emptyMap())
}
