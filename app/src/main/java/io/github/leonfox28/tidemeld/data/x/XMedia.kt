package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.data.model.*
import kotlinx.serialization.json.*

/** X's attachments become the same presentation values as every other platform. */
fun parseXMedia(entries: List<JsonElement>): List<MixedMedia> = entries.mapNotNull { entry ->
    val size = entry.at("original_info") ?: entry.at("sizes", "large")
    val width = (size.at("width") ?: size.at("w")).string()?.toIntOrNull() ?: 0
    val height = (size.at("height") ?: size.at("h")).string()?.toIntOrNull() ?: 0
    val cover = entry.at("media_url_https").string()
    when (entry.at("type").string()) {
        "photo" ->
            cover?.let {
                MixedMedia.Pic(
                    PicInfo(
                        entry.at("id_str").string() ?: it,
                        PicType.Pic,
                        listOf(PicVariant(it, width, height)),
                    )
                )
            }
        "video",
        "animated_gif" -> {
            val info = entry.at("video_info")
            val streams =
                (info.at("variants") as? JsonArray)
                    .orEmpty()
                    .filter { it.at("content_type").string() == "video/mp4" }
                    .sortedByDescending { it.at("bitrate").string()?.toLongOrNull() ?: 0 }
                    .mapNotNull { it.at("url").string() }
            val ratio =
                (info.at("aspect_ratio") as? JsonArray).orEmpty().mapNotNull {
                    it.string()?.toFloatOrNull()
                }
            MixedMedia.Video(
                VideoInfo(
                    coverUrl = cover,
                    duration =
                        info.at("duration_millis").string()?.toLongOrNull()?.div(1000)?.toInt(),
                    aspectRatio =
                        if (ratio.size == 2 && ratio[1] > 0) ratio[0] / ratio[1]
                        else if (width > 0 && height > 0) width.toFloat() / height else null,
                    streamUrls = streams,
                )
            )
        }
        else -> null
    }
}
