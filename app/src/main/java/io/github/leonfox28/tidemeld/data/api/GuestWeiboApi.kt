package io.github.leonfox28.tidemeld.data.api

import io.github.leonfox28.tidemeld.core.net.SessionExpiredException
import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import io.github.leonfox28.tidemeld.core.net.WeiboCookieJar
import io.github.leonfox28.tidemeld.core.net.WeiboHttp
import io.github.leonfox28.tidemeld.core.net.unwrapResponse
import io.github.leonfox28.tidemeld.core.util.devLog
import io.github.leonfox28.tidemeld.core.util.readBool
import io.github.leonfox28.tidemeld.core.util.readInt
import io.github.leonfox28.tidemeld.core.util.readMap
import io.github.leonfox28.tidemeld.core.util.readMaps
import io.github.leonfox28.tidemeld.data.model.Paged
import io.github.leonfox28.tidemeld.data.model.Status
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject
import okhttp3.Request

/** Mobile public feed on a separate visitor jar, never adopted by SessionController. */
class GuestWeiboApi(
    private val http: WeiboHttp,
    private val jar: WeiboCookieJar,
    private val prepare: suspend () -> Map<String, Map<String, String>>,
) {
    private var ready = false
    private val lock = Mutex()

    suspend fun fetchTimeline(): Paged<Status> = lock.withLock {
        if (!ready) {
            val cookies = prepare()
            jar.replaceAll(mapOf(WeiboCookieJar.MOBILE to cookies[WeiboCookieJar.MOBILE].orEmpty()))
            val config = get("/api/config")
            if (readBool(readMap(config["data"])?.get("login")) != false) {
                jar.clear()
                throw WeiboApiException("游客访问暂不可用，请登录微博后重试")
            }
            ready = true
            devLog("guest session: verified signed out")
        }
        try {
            parseTimeline(get("/api/container/getIndex?containerid=102803")).also {
                devLog("guest timeline: ${it.items.size} statuses")
            }
        } catch (e: SessionExpiredException) {
            ready = false
            jar.clear()
            throw WeiboApiException("微博暂不允许游客访问，请稍后重试或登录")
        }
    }

    private suspend fun get(path: String): JsonObject {
        val request =
            Request.Builder()
                .url("https://m.weibo.cn$path")
                .header("Referer", "https://m.weibo.cn/")
                .build()
        return unwrapResponse(http.send(request).toWeiboResponse())
    }

    companion object {
        fun parseTimeline(json: JsonObject): Paged<Status> {
            fun posts(cards: List<JsonObject>): List<Status> = cards.flatMap { card ->
                val post = Status.tryFromJson(card["mblog"])
                if (post != null)
                    listOf(
                        post.copy(
                            isAd =
                                post.isAd ||
                                    readBool(card["is_ad"]) == true ||
                                    readInt(card["is_ad"]) == 1L
                        )
                    )
                else posts(readMaps(card["card_group"]))
            }
            // The next page requires sign-in; never keep retrying it as a guest.
            return Paged(posts(readMaps(readMap(json["data"])?.get("cards"))))
        }
    }
}
