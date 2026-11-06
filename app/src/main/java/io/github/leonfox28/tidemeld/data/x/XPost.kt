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
    val replyToHandles: List<String> = emptyList(),
    val sensitive: Boolean = false,
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

data class XConversation(
    val post: XPost?,
    val replies: Paged<XPost>,
    val ancestors: List<XPost> = emptyList(),
)

fun parseXConversation(
    json: JsonObject,
    focalId: String,
    previousCursor: String? = null,
): XConversation {
    val instructions =
        json.at("data", "threaded_conversation_with_injections_v2", "instructions") as? JsonArray
            ?: throw WeiboApiException("X 暂时无法读取这条帖子的评论")
    val page = parseXEntries(instructions, previousCursor)
    val posts = page.items.distinctBy { it.originalId }.associateBy { it.originalId }
    val focal = posts[focalId]
    val ancestors = mutableListOf<XPost>()
    val visited = mutableSetOf(focalId)
    var parent = focal?.replyTo
    while (parent != null && visited.add(parent)) {
        val post = posts[parent] ?: break
        ancestors += post
        parent = post.replyTo
    }
    val related = mutableSetOf(focalId)
    repeat(page.items.size) {
        page.items
            .filter { it.originalId !in visited && it.replyTo in related }
            .forEach { related += it.originalId }
    }
    return XConversation(
        focal,
        Paged(
            page.items.filter {
                it.originalId != focalId && it.originalId in related
            },
            page.nextCursor,
        ),
        ancestors.asReversed(),
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
    val entries = (legacy.at("extended_entities", "media") as? JsonArray).orEmpty()
    val media = parseXMedia(entries)
    val content = xPostContent(legacy, note, entries)
    val photos = media.filterIsInstance<MixedMedia.Pic>().map { it.pic }
    val video = media.filterIsInstance<MixedMedia.Video>().firstOrNull()?.video
    return XPost(
        id,
        author,
        handle,
        user.at("avatar", "image_url").string()
            ?: user.at("legacy", "profile_image_url_https").string(),
        content.text,
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
        replyToHandles = content.replyToHandles,
        sensitive =
            (legacy["possibly_sensitive"] as? JsonPrimitive)?.booleanOrNull == true ||
                entries.any { media ->
                    listOf("adult_content", "graphic_violence", "other").any {
                        (media.at("sensitive_media_warning", it) as? JsonPrimitive)
                            ?.booleanOrNull == true
                    }
                },
    )
}

private data class XPostContent(val text: String, val replyToHandles: List<String>)

/** Hide only reply addressing and attachments that have another native presentation. */
private fun xPostContent(
    legacy: JsonObject,
    note: JsonElement?,
    media: List<JsonElement>,
): XPostContent {
    val noteText = note.at("text").string()
    var text = noteText ?: legacy["full_text"].string().orEmpty()
    val recipients = mutableListOf<String>()
    if (legacy["in_reply_to_status_id_str"].string() != null) {
        legacy["in_reply_to_screen_name"]
            .string()
            ?.takeIf { it.matches(Regex("[A-Za-z0-9_]{1,15}")) }
            ?.let(recipients::add)
        // A long note has its own text and offsets. Never crop it using the legacy preview's range.
        val range =
            (if (noteText != null) note.at("display_text_range") else legacy["display_text_range"])
                as? JsonArray
        val start = range?.getOrNull(0).string()?.toIntOrNull()
        val end = range?.getOrNull(1).string()?.toIntOrNull()
        if (
            range?.size == 2 &&
                start != null &&
                end != null &&
                start > 0 &&
                start <= end &&
                end <= text.length
        ) {
            val prefix = text.take(start)
            // Addressing contains ASCII handles and whitespace only, so no Unicode boundary is
            // split.
            if (prefix.matches(Regex("(?:@[A-Za-z0-9_]{1,15}\\s+)+"))) {
                recipients +=
                    Regex("@([A-Za-z0-9_]{1,15})").findAll(prefix).map { it.groupValues[1] }
                text = text.drop(start)
            }
        }
    }
    for (entry in media) {
        val represented = parseXMedia(listOf(entry)).singleOrNull()
        val visible =
            when (represented) {
                is MixedMedia.Pic -> true
                is MixedMedia.Video ->
                    represented.video.coverUrl != null || represented.video.streamUrls.isNotEmpty()
                null -> false
            }
        val url = entry.at("url").string()?.takeIf(String::isNotBlank) ?: continue
        if (!visible) continue
        // Match the entire token, never every t.co link or the prefix of another URL.
        val cleaned = text.replace(Regex("(?<!\\S)${Regex.escape(url)}(?=\\s|$)"), "")
        if (cleaned != text) text = cleaned.trim()
    }
    // Do not use the range's end to drop attachments we cannot render or truncate a long note.
    val urls =
        if (noteText != null) note.at("entity_set", "urls") else legacy.at("entities", "urls")
    (urls as? JsonArray)?.forEach { entity ->
        val short = entity.at("url").string()?.takeIf(String::isNotBlank)
        val expanded = entity.at("expanded_url").string()
        if (short != null && expanded != null) text = text.replace(short, expanded)
    }
    return XPostContent(
        Parser.unescapeEntities(text, false),
        recipients.distinctBy { it.lowercase(java.util.Locale.ROOT) },
    )
}
