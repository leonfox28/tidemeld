package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import io.github.leonfox28.tidemeld.core.util.readBool
import kotlinx.serialization.json.JsonObject

data class XUserRelationship(
    val following: Boolean,
    val followsYou: Boolean,
    val requested: Boolean,
    val blocking: Boolean,
    val showsReposts: Boolean?,
)

sealed interface XUserAction {
    data class Follow(val enabled: Boolean) : XUserAction

    data class Block(val enabled: Boolean) : XUserAction

    data class Reposts(val enabled: Boolean) : XUserAction
}

fun parseXRelationship(json: JsonObject, source: String, target: String): XUserRelationship {
    val from = json.at("relationship", "source")
    if (
        from.at("id_str").string() != source ||
            json.at("relationship", "target", "id_str").string() != target
    )
        throw WeiboApiException("无法确认用户关系，请刷新后重试")
    return XUserRelationship(
        readBool(from.at("following")) ?: throw WeiboApiException("无法确认关注状态"),
        readBool(from.at("followed_by")) == true,
        readBool(from.at("following_requested")) == true,
        readBool(from.at("blocking")) ?: throw WeiboApiException("无法确认拉黑状态"),
        readBool(from.at("want_retweets")),
    )
}
