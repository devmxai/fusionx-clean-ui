package com.fusionx.fusionx_clean_ui.engine

class FusionXTimelineProjectStore {
    private var canvas = FusionXProjectCanvas()
    private var tracks: List<FusionXProjectTrack> = emptyList()

    fun sync(payload: Map<String, Any?>) {
        val nextTracks = parseTracks(payload["tracks"])
        tracks = nextTracks

        val firstVisualClip = nextTracks
            .asSequence()
            .flatMap { it.clips.asSequence() }
            .firstOrNull { it.isVisual }

        if (firstVisualClip == null) {
            canvas = FusionXProjectCanvas()
            return
        }

        if (!canvas.isLocked) {
            canvas.tryLock(
                width = firstVisualClip.sourceWidth,
                height = firstVisualClip.sourceHeight,
            )
        }
    }

    fun currentCanvasSnapshot(): Map<String, Any?> = canvas.toMap()

    fun projectDurationUs(): Long {
        return tracks
            .asSequence()
            .flatMap { it.clips.asSequence() }
            .map { it.timelineEndUs }
            .maxOrNull() ?: 0L
    }

    fun resolvePlaybackAtTimelineTimeUs(timelineTimeUs: Long): Map<String, Any?> {
        val visualClips = tracks
            .filter { it.kind == "video" || it.kind == "image" }
            .flatMap { track ->
                track.clips.map { clip -> track to clip }
            }
            .sortedWith(
                compareBy<Pair<FusionXProjectTrack, FusionXProjectClip>>(
                    { it.first.layerIndex },
                    { it.second.timelineStartUs },
                ),
            )

        if (visualClips.isEmpty()) {
            return mapOf(
                "hasActiveClip" to false,
                "projectDurationUs" to 0L,
            )
        }

        val projectDurationUs = visualClips.maxOf { it.second.timelineEndUs }
        val clampedTimelineTimeUs = when {
            projectDurationUs <= 0L -> 0L
            timelineTimeUs < 0L -> 0L
            timelineTimeUs >= projectDurationUs -> projectDurationUs - 1L
            else -> timelineTimeUs
        }

        val activeIndex = visualClips.indexOfFirst { (_, clip) ->
            clampedTimelineTimeUs >= clip.timelineStartUs &&
                clampedTimelineTimeUs < clip.timelineEndUs
        }
        if (activeIndex < 0) {
            return mapOf(
                "hasActiveClip" to false,
                "projectDurationUs" to projectDurationUs,
            )
        }

        val (track, clip) = visualClips[activeIndex]
        val nextClip = visualClips.getOrNull(activeIndex + 1)?.second
        val clipLocalTimeUs = (clampedTimelineTimeUs - clip.timelineStartUs).coerceAtLeast(0L)
        val sourceTimeUs = clip.sourceOffsetUs + clipLocalTimeUs

        return mapOf(
            "hasActiveClip" to true,
            "projectDurationUs" to projectDurationUs,
            "timelineTimeUs" to clampedTimelineTimeUs,
            "activeTrackId" to track.id,
            "activeTrackKind" to track.kind,
            "activeLayerIndex" to track.layerIndex,
            "activeClipId" to clip.id,
            "activeAssetId" to clip.assetId,
            "activePath" to clip.path,
            "activeMediaType" to clip.mediaType,
            "activeLabel" to clip.label,
            "activeClipTimelineStartUs" to clip.timelineStartUs,
            "activeClipTimelineEndUs" to clip.timelineEndUs,
            "activeClipDurationUs" to clip.durationUs,
            "activeClipLocalTimeUs" to clipLocalTimeUs,
            "activeSourceOffsetUs" to clip.sourceOffsetUs,
            "activeSourceTimeUs" to sourceTimeUs,
            "nextClipId" to nextClip?.id,
            "nextAssetId" to nextClip?.assetId,
            "nextPath" to nextClip?.path,
            "nextTimelineStartUs" to nextClip?.timelineStartUs,
            "nextDurationUs" to nextClip?.durationUs,
            "nextSourceOffsetUs" to nextClip?.sourceOffsetUs,
        )
    }

    private fun parseTracks(raw: Any?): List<FusionXProjectTrack> {
        val rawTracks = raw as? List<*> ?: return emptyList()
        return rawTracks.mapNotNull { trackEntry ->
            val trackMap = trackEntry as? Map<*, *> ?: return@mapNotNull null
            FusionXProjectTrack(
                id = trackMap.string("id"),
                kind = trackMap.string("kind"),
                layerIndex = trackMap.int("layerIndex"),
                clips = parseClips(trackMap["clips"]),
            )
        }
    }

    private fun parseClips(raw: Any?): List<FusionXProjectClip> {
        val rawClips = raw as? List<*> ?: return emptyList()
        return rawClips.mapNotNull { clipEntry ->
            val clipMap = clipEntry as? Map<*, *> ?: return@mapNotNull null
            FusionXProjectClip(
                id = clipMap.string("id"),
                assetId = clipMap.stringOrNull("assetId"),
                path = clipMap.stringOrNull("path"),
                mediaType = clipMap.string("mediaType"),
                label = clipMap.stringOrNull("label"),
                durationUs = clipMap.long("durationUs"),
                sourceOffsetUs = clipMap.long("sourceOffsetUs"),
                timelineStartUs = clipMap.long("timelineStartUs"),
                sourceWidth = clipMap.int("sourceWidth"),
                sourceHeight = clipMap.int("sourceHeight"),
            )
        }
    }

    private data class FusionXProjectTrack(
        val id: String,
        val kind: String,
        val layerIndex: Int,
        val clips: List<FusionXProjectClip>,
    )

    private data class FusionXProjectClip(
        val id: String,
        val assetId: String?,
        val path: String?,
        val mediaType: String,
        val label: String?,
        val durationUs: Long,
        val sourceOffsetUs: Long,
        val timelineStartUs: Long,
        val sourceWidth: Int,
        val sourceHeight: Int,
    ) {
        val isVisual: Boolean
            get() = mediaType == "video" || mediaType == "image"

        val timelineEndUs: Long
            get() = timelineStartUs + durationUs.coerceAtLeast(0L)
    }

    private data class FusionXProjectCanvas(
        var width: Int = 0,
        var height: Int = 0,
        var aspectRatio: Double = 0.0,
        var isLocked: Boolean = false,
    ) {
        fun tryLock(width: Int, height: Int): Boolean {
            if (isLocked || width <= 0 || height <= 0) {
                return false
            }
            this.width = width
            this.height = height
            aspectRatio = width.toDouble() / height.toDouble()
            isLocked = true
            return true
        }

        fun toMap(): Map<String, Any?> = mapOf(
            "width" to width,
            "height" to height,
            "aspectRatio" to aspectRatio,
            "isLocked" to isLocked,
        )
    }

    private fun Map<*, *>.string(key: String): String {
        return stringOrNull(key) ?: ""
    }

    private fun Map<*, *>.stringOrNull(key: String): String? {
        return this[key] as? String
    }

    private fun Map<*, *>.int(key: String): Int {
        return (this[key] as? Number)?.toInt() ?: 0
    }

    private fun Map<*, *>.long(key: String): Long {
        return (this[key] as? Number)?.toLong() ?: 0L
    }
}
