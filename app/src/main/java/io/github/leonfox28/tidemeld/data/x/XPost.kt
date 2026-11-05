package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import io.github.leonfox28.tidemeld.core.util.parseWeiboDate
import io.github.leonfox28.tidemeld.core.util.readString
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.data.model.Paged
import io.github.leonfox28.tidemeld.data.model.PicInfo
import io.github.leonfox28.tidemeld.data.model.VideoInfo
import java.time.Instant
import kotlinx.serialization.json.*
import org.jsoup.parser.Parser

data class XPost(
    val id: String,
    val author: String,
    val handle: String,
    val avatar: String?,
    val text: String,
    val createdAt: Instant?,
    val pictures: List<PicInfo> = emptyList(),
    val videoCover: String? = null,
    val videoUrl: String? = null,
    val quote: XPost? = null,
    val repostedBy: String? = null,
    val promoted: Boolean = false,
    val originalId: String = id,
    val metrics: XMetrics = XMetrics(),
    val replyTo: String? = null,
    val attachments: List<MixedMedia> = emptyList(),
) {
    val media: List<MixedMedia>
        get() = attachments.ifEmpty {
            pictures.map(MixedMedia::Pic) +
                if (videoCover != null || videoUrl != null)
                    listOf(
                        MixedMedia.Video(
                            VideoInfo(coverUrl = videoCover, streamUrls = listOfNotNull(videoUrl))
                        )
                    )
                else emptyList()
        }

    val url
        get() = "https://x.com/$handle/status/$originalId"
}

data class XMetrics(
    val likes: Int = 0,
    val reposts: Int = 0,
    val replies: Int = 0,
    val liked: Boolean = false,
    val reposted: Boolean = false,
)

data class XConversation(val post: XPost?, val replies: Paged<XPost>)

fun parseXConversation(
    json: JsonObject,
    focalId: String,
    previousCursor: String? = null,
): XConversation {
    val instructions =
        json.at("data", "threaded_conversation_with_injections_v2", "instructions") as? JsonArray
            ?: throw WeiboApiException("X 暂时无法读取这条帖子的评论")
    val page = parseXEntries(instructions, previousCursor)
    val related = mutableSetOf(focalId)
    repeat(page.items.size) {
        page.items.filter { it.replyTo in related }.forEach { related += it.originalId }
    }
    return XConversation(
        page.items.firstOrNull { it.originalId == focalId },
        Paged(
            page.items.filter {
                it.originalId != focalId && it.originalId in related
            },
            page.nextCursor,
        ),
    )
}

internal fun JsonElement?.obj() = this as? JsonObject

internal fun JsonElement?.at(vararg keys: String): JsonElement? =
    keys.fold(this) { value, key -> value.obj()?.get(key) }

internal fun JsonElement?.string() = readString(this)

/** Only timeline entries are traversed: quoted posts must not leak into the outer feed. */
fun parseXTimeline(json: JsonObject, previousCursor: String? = null): Paged<XPost> {
    val instructions =
        json.at("data", "home", "home_timeline_urt", "instructions") as? JsonArray
            ?: throw WeiboApiException("X 信息流格式已变化，请稍后更新应用")
    return parseXEntries(instructions, previousCursor)
}

private fun parseXEntries(instructions: JsonArray, previousCursor: String?): Paged<XPost> {
    val posts = mutableListOf<XPost>()
    var cursor: String? = null
    fun content(value: JsonElement?) {
        if (value.at("cursorType").string() == "Bottom") cursor = value.at("value").string()
        val item = value.at("itemContent") ?: value
        val result = item.at("tweet_results", "result")
        if (result != null) parseXPost(result, item.at("promotedMetadata") != null)?.let(posts::add)
        (value.at("items") as? JsonArray)?.forEach { child ->
            val nested = child.at("item", "itemContent")
            parseXPost(nested.at("tweet_results", "result"), nested.at("promotedMetadata") != null)
                ?.let(posts::add)
        }
    }
    for (instruction in instructions) {
        (instruction.at("entries") as? JsonArray)?.forEach { content(it.at("content")) }
        instruction.at("entry")?.let { content(it.at("content")) }
    }
    // Filter before deduplication so a promoted placement cannot hide an organic copy.
    return Paged(
        posts.filterNot { it.promoted }.distinctBy { it.id },
        nextCursor = cursor?.takeIf { it != previousCursor },
    )
}

fun parseXPost(value: JsonElement?, promoted: Boolean = false, depth: Int = 0): XPost? {
    if (depth > 3) return null
    val root = (value.at("tweet") ?: value).obj() ?: return null
    val id = root["rest_id"].string() ?: return null
    val legacy = root["legacy"].obj() ?: return null
    val user = root.at("core", "user_results", "result")
    val handle =
        user.at("core", "screen_name").string()
            ?: user.at("legacy", "screen_name").string()
            ?: return null
    if (!handle.matches(Regex("[A-Za-z0-9_]+"))) return null
    val author = user.at("core", "name").string() ?: user.at("legacy", "name").string() ?: handle
    val repost = legacy.at("retweeted_status_result", "result")
    if (repost != null)
        return parseXPost(repost, promoted, depth + 1)
            ?.copy(
                id = id,
                repostedBy = author,
                createdAt = parseWeiboDate(legacy["created_at"].string()),
            )
    val note = root.at("note_tweet", "note_tweet_results", "result")
    var text = note.at("text").string() ?: legacy["full_text"].string().orEmpty()
    val urls = note.at("entity_set", "urls") ?: legacy.at("entities", "urls")
    (urls as? JsonArray)?.forEach { entity ->
        val short = entity.at("url").string()
        val long = entity.at("expanded_url").string()
        if (short != null && long != null) text = text.replace(short, long)
    }
    val media = parseXMedia((legacy.at("extended_entities", "media") as? JsonArray).orEmpty())
    val photos = media.filterIsInstance<MixedMedia.Pic>().map { it.pic }
    val video = media.filterIsInstance<MixedMedia.Video>().firstOrNull()?.video
    return XPost(
        id,
        author,
        handle,
        user.at("avatar", "image_url").string()
            ?: user.at("legacy", "profile_image_url_https").string(),
        Parser.unescapeEntities(text, false),
        parseWeiboDate(legacy["created_at"].string()),
        photos,
        video?.coverUrl,
        video?.streamUrls?.firstOrNull(),
        parseXPost(root.at("quoted_status_result", "result"), depth = depth + 1),
        promoted = promoted,
        metrics =
            XMetrics(
                likes = legacy["favorite_count"].string()?.toIntOrNull()?.coerceAtLeast(0) ?: 0,
                reposts = legacy["retweet_count"].string()?.toIntOrNull()?.coerceAtLeast(0) ?: 0,
                replies = legacy["reply_count"].string()?.toIntOrNull()?.coerceAtLeast(0) ?: 0,
                liked = (legacy["favorited"] as? JsonPrimitive)?.booleanOrNull == true,
                reposted = (legacy["retweeted"] as? JsonPrimitive)?.booleanOrNull == true,
            ),
        replyTo = legacy["in_reply_to_status_id_str"].string(),
        attachments = media,
    )
}
