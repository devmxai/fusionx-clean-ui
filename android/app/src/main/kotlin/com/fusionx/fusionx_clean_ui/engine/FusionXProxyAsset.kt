package com.fusionx.fusionx_clean_ui.engine

data class FusionXProxyAsset(
    val path: String,
    val shortSide: Int,
    val sourceDurationUs: Long,
    val proxyDurationUs: Long,
)
