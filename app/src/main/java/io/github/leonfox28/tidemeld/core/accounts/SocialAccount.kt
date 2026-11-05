package io.github.leonfox28.tidemeld.core.accounts

import io.github.leonfox28.tidemeld.core.session.StoredSession
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

enum class SocialPlatform(val key: String, val label: String, val domains: List<String>) {
    Weibo("weibo", "微博", listOf("weibo.com", "weibo.cn", "sina.com.cn")),
    X("x", "X", listOf("x.com", "twitter.com")),
}

enum class FeedSelection(val key: String, val label: String, val platform: SocialPlatform?) {
    All("all", "聚合", null),
    Weibo("weibo", "微博", SocialPlatform.Weibo),
    X("x", "X", SocialPlatform.X),
}

/** The platform is part of identity; numerical user IDs can overlap. */
data class SocialAccount(
    val platform: SocialPlatform,
    val session: StoredSession,
    val expired: Boolean = false,
    val revision: Long = 0,
) {
    val key: String
        get() = "${platform.key}:${session.account.uid}"

    val name: String
        get() = session.account.screenName ?: session.account.uid

    fun toJson(): JsonObject = buildJsonObject {
        put("platform", platform.key)
        put("session", session.toJson())
        put("expired", expired)
    }

    companion object {
        fun fromJson(json: JsonObject): SocialAccount =
            SocialAccount(
                SocialPlatform.entries.first {
                    it.key == json.getValue("platform").jsonPrimitive.content
                },
                StoredSession.fromJson(json.getValue("session").jsonObject),
                json["expired"]?.jsonPrimitive?.booleanOrNull ?: false,
            )
    }
}
