package io.github.leonfox28.tidemeld.core.media

import io.github.leonfox28.tidemeld.data.model.PicInfo

/** Platform adapters supply content and refresh behavior; players own only playback state. */
class VideoRequest(
    val cover: String?,
    val headers: Map<String, String>,
    val resolve: suspend (refresh: Boolean) -> VideoSource,
)

class PhotoMotion(
    val headers: Map<String, String>,
    val canRefresh: Boolean,
    val resolve: suspend (PicInfo, refresh: Boolean) -> VideoSource,
)
