package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import io.github.leonfox28.tidemeld.data.model.Paged
import kotlinx.serialization.json.*

data class XProfileUser(
    val id: String? = null,
    val handle: String? = null,
    val name: String? = null,
    val avatar: String? = null,
)

data class XUserProfile(
    val user: XProfileUser,
    val description: String?,
    val coverUrl: String?,
    val location: String?,
    val followers: Long?,
    val following: Long?,
    val posts: Long?,
    val followsYou: Boolean,
    val followed: Boolean,
    val verified: Boolean,
    val protected: Boolean,
)

fun parseXProfile(json: JsonObject): XUserProfile {
    val result = json.at("data", "user", "result")
    val id = result.at("rest_id").string()?.takeIf { it.isNotBlank() }
    val handle =
        result.at("core", "screen_name").string() ?: result.at("legacy", "screen_name").string()
    if (id == null || handle == null || !Regex("[A-Za-z0-9_]{1,15}").matches(handle))
        throw WeiboApiException("用户不存在或暂时无法查看")
    val legacy = result.at("legacy")
    fun count(key: String) = (legacy.at(key) as? JsonPrimitive)?.longOrNull?.coerceAtLeast(0)
    fun flag(section: String, key: String) =
        (result.at(section, key) as? JsonPrimitive)?.booleanOrNull
            ?: (legacy.at(key) as? JsonPrimitive)?.booleanOrNull
            ?: false
    return XUserProfile(
        XProfileUser(
            id,
            handle,
            result.at("core", "name").string() ?: legacy.at("name").string() ?: handle,
            result.at("avatar", "image_url").string()
                ?: legacy.at("profile_image_url_https").string(),
        ),
        (result.at("profile_bio", "description").string() ?: legacy.at("description").string())
            ?.takeIf { it.isNotBlank() },
        legacy.at("profile_banner_url").string(),
        (result.at("location", "location").string() ?: legacy.at("location").string())?.takeIf {
            it.isNotBlank()
        },
        count("followers_count"),
        count("friends_count"),
        count("statuses_count"),
        flag("relationship_perspectives", "followed_by"),
        flag("relationship_perspectives", "following"),
        (result.at("is_blue_verified") as? JsonPrimitive)?.booleanOrNull == true ||
            flag("verification", "verified"),
        flag("privacy", "protected"),
    )
}

fun parseXUserPosts(json: JsonObject, previousCursor: String? = null): Paged<XPost> {
    val user = json.at("data", "user", "result")
    val instructions =
        (user.at("timeline_v2", "timeline", "instructions")
            ?: user.at("timeline", "timeline", "instructions"))
            as? JsonArray ?: throw WeiboApiException("暂时无法查看这个用户的帖子，请在 X 网页检查访问权限")
    return parseXEntries(instructions, previousCursor)
}
