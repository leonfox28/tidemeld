package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.net.*
import io.github.leonfox28.tidemeld.core.session.StoredSession
import io.github.leonfox28.tidemeld.data.model.Account
import io.github.leonfox28.tidemeld.data.model.Paged
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

/** First-party web requests only. Cookies are never sent to assets, redirects or third parties. */
class XWebApi(
    base: OkHttpClient,
    private val protocol: JsonObject,
    private val throttle: RequestThrottle = RequestThrottle(),
) {
    private val client =
        base
            .newBuilder()
            .cookieJar(CookieJar.NO_COOKIES)
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .callTimeout(25, TimeUnit.SECONDS)
            .build()

    suspend fun verify(input: Map<String, String>): StoredSession {
        val cookies = input.toMutableMap()
        if (cookies["auth_token"].isNullOrBlank() || cookies["ct0"].isNullOrBlank())
            throw SessionExpiredException()
        val home = get("https://x.com/home".toHttpUrl(), cookies, api = false)
        val uid =
            Regex("\"user_id\"\\s*:\\s*\"(\\d+)\"").find(home)?.groupValues?.get(1)
                ?: throw WeiboApiException("尚未确认 X 登录，请完成网页登录后重试")
        val json =
            query(
                "UserByRestId",
                buildJsonObject {
                    put("userId", uid)
                    put("withSafetyModeUserFields", true)
                },
                cookies,
            )
        val user = json.at("data", "user", "result")
        if (user.at("rest_id").string() != uid) throw SessionExpiredException()
        val name =
            user.at("core", "name").string()
                ?: user.at("legacy", "name").string()
                ?: user.at("legacy", "screen_name").string()
        return StoredSession(Account(uid, name), mapOf("x.com" to cookies))
    }

    suspend fun timeline(
        session: StoredSession,
        cursor: String?,
        onCookies: (Map<String, Map<String, String>>) -> Unit = {},
    ): Paged<XPost> {
        val cookies = session.cookies["x.com"].orEmpty().toMutableMap()
        val variables = buildJsonObject {
            put("count", 20)
            put("includePromotedContent", true)
            put("latestControlAvailable", true)
            put("withCommunity", true)
            put("enableRanking", false)
            put("requestContext", if (cursor == null) "launch" else "scroll")
            put("seenTweetIds", JsonArray(emptyList()))
            cursor?.let { put("cursor", it) }
        }
        try {
            return parseXTimeline(query("HomeLatestTimeline", variables, cookies), cursor)
        } finally {
            if (cookies != session.cookies["x.com"]) onCookies(mapOf("x.com" to cookies.toMap()))
        }
    }

    suspend fun conversation(
        session: StoredSession,
        id: String,
        cursor: String?,
        onCookies: (Map<String, Map<String, String>>) -> Unit = {},
    ): XConversation =
        withSession(session, onCookies) { cookies ->
            val variables = buildJsonObject {
                put("focalTweetId", id)
                put("referrer", "home")
                put("with_rux_injections", false)
                put("rankingMode", "Relevance")
                put("includePromotedContent", true)
                put("withCommunity", true)
                put("withQuickPromoteEligibilityTweetFields", true)
                put("withBirdwatchNotes", true)
                put("withVoice", true)
                cursor?.let { put("cursor", it) }
            }
            parseXConversation(query("TweetDetail", variables, cookies), id, cursor)
        }

    suspend fun like(
        session: StoredSession,
        id: String,
        liked: Boolean,
        onCookies: (Map<String, Map<String, String>>) -> Unit = {},
        isCurrent: () -> Boolean = { true },
    ) =
        withSession(session, onCookies) { cookies ->
            val result =
                query(
                    if (liked) "FavoriteTweet" else "UnfavoriteTweet",
                    buildJsonObject { put("tweet_id", id) },
                    cookies,
                    write = true,
                    isCurrent = isCurrent,
                )
            if (
                result.at("data", if (liked) "favorite_tweet" else "unfavorite_tweet").string() !=
                    "Done"
            )
                throw WeiboApiException(WRITE_UNCERTAIN)
        }

    suspend fun repost(
        session: StoredSession,
        id: String,
        reposted: Boolean,
        onCookies: (Map<String, Map<String, String>>) -> Unit = {},
        isCurrent: () -> Boolean = { true },
    ) =
        withSession(session, onCookies) { cookies ->
            val result =
                query(
                    if (reposted) "CreateRetweet" else "DeleteRetweet",
                    buildJsonObject {
                        put(if (reposted) "tweet_id" else "source_tweet_id", id)
                        put("dark_request", false)
                    },
                    cookies,
                    write = true,
                    isCurrent = isCurrent,
                )
            val acknowledged =
                if (reposted)
                    result
                        .at("data", "create_retweet", "retweet_results", "result", "rest_id")
                        .string() != null
                else
                    result
                        .at("data", "unretweet", "source_tweet_results", "result", "rest_id")
                        .string() == id
            if (!acknowledged) throw WeiboApiException(WRITE_UNCERTAIN)
        }

    suspend fun publish(
        session: StoredSession,
        post: XPost,
        text: String,
        quote: Boolean = false,
        onCookies: (Map<String, Map<String, String>>) -> Unit = {},
        isCurrent: () -> Boolean = { true },
    ): String =
        withSession(session, onCookies) { cookies ->
            if (text.isBlank()) throw WeiboApiException("请输入内容")
            val variables = buildJsonObject {
                put("tweet_text", text.trim())
                put("dark_request", false)
                putJsonObject("media") {
                    put("media_entities", JsonArray(emptyList()))
                    put("possibly_sensitive", false)
                }
                put("semantic_annotation_ids", JsonArray(emptyList()))
                if (quote) put("attachment_url", post.url)
                else
                    putJsonObject("reply") {
                        put("in_reply_to_tweet_id", post.originalId)
                        put("exclude_reply_user_ids", JsonArray(emptyList()))
                    }
            }
            val result =
                query("CreateTweet", variables, cookies, write = true, isCurrent = isCurrent)
            result.at("data", "create_tweet", "tweet_results", "result", "rest_id").string()
                ?: result
                    .at("data", "create_tweet", "tweet_results", "result", "tweet", "rest_id")
                    .string()
                ?: throw WeiboApiException(WRITE_UNCERTAIN)
        }

    private suspend fun <T> withSession(
        session: StoredSession,
        onCookies: (Map<String, Map<String, String>>) -> Unit,
        action: suspend (MutableMap<String, String>) -> T,
    ): T {
        val cookies = session.cookies["x.com"].orEmpty().toMutableMap()
        if (cookies["auth_token"].isNullOrBlank() || cookies["ct0"].isNullOrBlank())
            throw SessionExpiredException()
        try {
            return action(cookies)
        } finally {
            if (cookies != session.cookies["x.com"]) onCookies(mapOf("x.com" to cookies.toMap()))
        }
    }

    private suspend fun query(
        operation: String,
        variables: JsonObject,
        cookies: MutableMap<String, String>,
        write: Boolean = false,
        isCurrent: () -> Boolean = { true },
    ): JsonObject {
        val spec =
            protocol.at("operations", operation).obj() ?: throw WeiboApiException("X 接口配置不可用")
        val builder =
            "https://api.x.com/graphql/${spec["queryId"].string()}/$operation"
                .toHttpUrl()
                .newBuilder()
        val body =
            if (write)
                buildJsonObject {
                    put("variables", variables)
                    put("queryId", spec["queryId"]!!)
                    spec["features"]?.let { put("features", it) }
                }
                    .toString()
            else null
        if (!write) {
            builder.addQueryParameter("variables", variables.toString())
            spec["features"]?.let { builder.addQueryParameter("features", it.toString()) }
            spec["fieldToggles"]?.let { builder.addQueryParameter("fieldToggles", it.toString()) }
        }
        val text = get(builder.build(), cookies, api = true, body = body, isCurrent = isCurrent)
        val result =
            runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull()
                ?: throw WeiboApiException(if (write) WRITE_UNCERTAIN else "X 返回了无法识别的内容")
        val errors = result["errors"] as? JsonArray
        val code = errors?.firstOrNull().at("code").string()?.toIntOrNull()
        if (code in listOf(32, 89, 215)) throw SessionExpiredException()
        if (code == 88) {
            throttle.backOff()
            throw RateLimitedException(429)
        }
        if (!errors.isNullOrEmpty() && (write || result["data"] == null)) {
            val message =
                when (code) {
                    186 -> "内容超过 X 的长度限制，请缩短后重试"
                    187 -> "X 提示内容重复，请先刷新确认是否已发送"
                    226 -> "X 暂时限制了这次操作，请在官方网页检查账号状态"
                    else -> if (write) "X 未确认这次操作，请刷新帖子检查状态" else "X 暂时无法读取，请在官方网页检查账号状态"
                }
            throw WeiboApiException(message)
        }
        return result
    }

    private suspend fun get(
        url: HttpUrl,
        cookies: MutableMap<String, String>,
        api: Boolean,
        body: String? = null,
        isCurrent: () -> Boolean = { true },
    ): String {
        require(url.scheme == "https" && url.host in setOf("x.com", "api.x.com"))
        throttle.acquire()
        try {
            return withContext(Dispatchers.IO) {
                if (!isCurrent()) throw WeiboApiException("账号已变更，操作已取消")
                val request =
                    Request.Builder()
                        .url(url)
                        .header("User-Agent", BROWSER_USER_AGENT)
                        .header(
                            "Cookie",
                            cookies.entries
                                .filter { (name, value) ->
                                    !name.contains('\n') &&
                                        !value.contains('\n') &&
                                        !value.contains('\r')
                                }
                                .joinToString("; ") { "${it.key}=${it.value}" },
                        )
                        .header("Referer", "https://x.com/")
                if (api)
                    request
                        .header("Authorization", "Bearer $WEB_BEARER")
                        .header("x-csrf-token", cookies["ct0"].orEmpty())
                        .header("x-twitter-auth-type", "OAuth2Session")
                        .header("x-twitter-active-user", "yes")
                        .header("x-twitter-client-language", "zh-cn")
                if (body != null) request.post(body.toRequestBody("application/json".toMediaType()))
                client.newCall(request.build()).execute().use { response ->
                    when {
                        response.code == 401 -> throw SessionExpiredException()
                        response.code == 429 -> {
                            throttle.backOff()
                            throw RateLimitedException(429)
                        }
                        response.code == 403 ->
                            throw WeiboApiException("X 拒绝了请求，请在官方网页检查登录或安全验证", 403)
                        response.code in 300..399 ->
                            throw WeiboApiException("请完成 X 官方网页登录后重试", response.code)
                        !response.isSuccessful ->
                            throw WeiboApiException(
                                if (body != null && response.code >= 500) WRITE_UNCERTAIN
                                else "X 请求失败（${response.code}）",
                                response.code,
                            )
                    }
                    for (cookie in Cookie.parseAll(response.request.url, response.headers)) {
                        if (cookie.domain == "x.com" || cookie.domain == "api.x.com") {
                            if (cookie.expiresAt <= System.currentTimeMillis())
                                cookies.remove(cookie.name)
                            else cookies[cookie.name] = cookie.value
                        }
                    }
                    response.body.string()
                }
            }
        } catch (error: IOException) {
            if (body != null) throw WeiboApiException(WRITE_UNCERTAIN)
            throw NetworkException(error)
        } finally {
            throttle.release()
        }
    }

    companion object {
        const val WRITE_UNCERTAIN = "操作结果未确认，请先刷新帖子检查，避免重复发送"
        // Public identifier shipped by X's web client, not a user's developer credential.
        private const val WEB_BEARER =
            "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    }
}
