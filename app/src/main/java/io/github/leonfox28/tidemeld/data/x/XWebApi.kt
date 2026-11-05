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

    private suspend fun query(
        operation: String,
        variables: JsonObject,
        cookies: MutableMap<String, String>,
    ): JsonObject {
        val spec =
            protocol.at("operations", operation).obj() ?: throw WeiboApiException("X 接口配置不可用")
        val url =
            "https://api.x.com/graphql/${spec["queryId"].string()}/$operation"
                .toHttpUrl()
                .newBuilder()
                .addQueryParameter("variables", variables.toString())
                .addQueryParameter("features", spec["features"].toString())
                .build()
        val text = get(url, cookies, api = true)
        val result =
            runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull()
                ?: throw WeiboApiException("X 返回了无法识别的内容")
        val errors = result["errors"] as? JsonArray
        val code = errors?.firstOrNull().at("code").string()?.toIntOrNull()
        if (code in listOf(32, 89, 215)) throw SessionExpiredException()
        if (code == 88) {
            throttle.backOff()
            throw RateLimitedException(429)
        }
        if (!errors.isNullOrEmpty() && result["data"] == null)
            throw WeiboApiException("X 暂时无法读取，请在官方网页检查账号状态")
        return result
    }

    private suspend fun get(
        url: HttpUrl,
        cookies: MutableMap<String, String>,
        api: Boolean,
    ): String {
        require(url.scheme == "https" && url.host in setOf("x.com", "api.x.com"))
        throttle.acquire()
        try {
            return withContext(Dispatchers.IO) {
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
                            throw WeiboApiException("X 加载失败（${response.code}）", response.code)
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
            throw NetworkException(error)
        } finally {
            throttle.release()
        }
    }

    companion object {
        // Public identifier shipped by X's web client, not a user's developer credential.
        private const val WEB_BEARER =
            "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    }
}
