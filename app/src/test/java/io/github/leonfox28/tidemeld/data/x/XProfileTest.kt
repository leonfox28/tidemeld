package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.net.*
import io.github.leonfox28.tidemeld.core.session.StoredSession
import io.github.leonfox28.tidemeld.data.model.Account
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.x.xProfileHandle
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

internal const val xProfileFixture =
    """{"data":{"user":{"result":{"rest_id":"42","core":{"name":"合成用户","screen_name":"fixture"},"avatar":{"image_url":"https://media.test/avatar.jpg"},"location":{"location":"合成地点"},"privacy":{"protected":true},"relationship_perspectives":{"following":true,"followed_by":true},"is_blue_verified":true,"legacy":{"description":"合成简介","friends_count":12,"followers_count":345,"statuses_count":2}}}}}"""

internal fun xProfileEntry(id: String, promoted: Boolean = false) =
    """{"content":{"itemContent":{"tweet_results":{"result":{"rest_id":"$id","core":{"user_results":{"result":{"rest_id":"42","core":{"name":"合成用户","screen_name":"fixture"}}}},"legacy":{"full_text":"合成帖子$id"}}}${if (promoted) ",\"promotedMetadata\":{}" else ""}}}}"""

internal fun xProfilePosts(ids: List<String> = listOf("1"), cursor: String? = null): String {
    val entries =
        ids.map { xProfileEntry(it) } +
            listOfNotNull(cursor?.let { """{"content":{"cursorType":"Bottom","value":"$it"}}""" })
    return """{"data":{"user":{"result":{"timeline_v2":{"timeline":{"instructions":[{"entries":[${entries.joinToString(",")}]}]}}}}}}"""
}

internal fun xProfileApi(web: FakeWeibo) =
    XWebApi(
        web.client,
        buildJsonObject {
            putJsonObject("operations") {
                listOf("UserByRestId", "UserByScreenName", "UserTweets").forEach { name ->
                    putJsonObject(name) { put("queryId", "fixture") }
                }
            }
        },
        RequestThrottle(minIntervalMs = 0),
    )

internal fun xProfileSession(id: String) =
    StoredSession(
        Account(id),
        mapOf("x.com" to mapOf("auth_token" to "synthetic-$id", "ct0" to "csrf-$id")),
    )

@RunWith(RobolectricTestRunner::class)
class XProfileTest {
    private fun parse(text: String) = Json.parseToJsonElement(text).jsonObject

    @Test
    fun `modern and legacy profiles keep identity counts and protected state`() {
        val p = parseXProfile(parse(xProfileFixture))
        assertEquals("42", p.user.id)
        assertEquals("fixture", p.user.handle)
        assertEquals(345L, p.followers)
        assertTrue(p.followed && p.followsYou && p.verified && p.protected)
        assertEquals("合成地点", p.location)
        val legacy =
            parseXProfile(
                parse(
                    """{"data":{"user":{"result":{"rest_id":"43","legacy":{"name":"旧结构","screen_name":"old"}}}}}"""
                )
            )
        assertEquals("旧结构", legacy.user.name)
        assertNull(legacy.posts)
        assertThrows(WeiboApiException::class.java) {
            parseXProfile(
                parse("""{"data":{"user":{"result":{"__typename":"UserUnavailable"}}}}""")
            )
        }
        assertThrows(WeiboApiException::class.java) {
            parseXUserPosts(parse("""{"data":{"user":{"result":{}}}}"""))
        }
    }

    @Test
    fun `pinned post stays first ads disappear and repeated cursor ends pagination`() {
        val json =
            parse(
                """{"data":{"user":{"result":{"timeline":{"timeline":{"instructions":[{"type":"TimelinePinEntry","entry":${xProfileEntry("1")}},{"entries":[${xProfileEntry("1")},${xProfileEntry("2", true)},{"content":{"cursorType":"Bottom","value":"next"}}]}]}}}}}}"""
            )
        val page = parseXUserPosts(json)
        assertEquals(listOf("1"), page.items.map { it.id })
        assertTrue(page.items.single().pinned)
        assertEquals("42", page.items.single().authorId)
        assertEquals("next", page.nextCursor)
        assertNull(parseXUserPosts(json, "next").nextCursor)
        assertTrue(parseXUserPosts(parse(xProfilePosts(emptyList()))).items.isEmpty())
    }

    @Test
    fun `native profile URLs exclude application routes and other hosts`() {
        assertEquals("Fixture", xProfileHandle("https://twitter.com/Fixture/"))
        listOf(
                "https://x.com/home",
                "https://x.com/search?q=fixture",
                "https://x.com/fixture/status/1",
                "https://evil.test/fixture",
                "https://x.com/name-with-dash",
            )
            .forEach { assertNull(xProfileHandle(it)) }
    }

    @Test
    fun `profile and pagination use the chosen account and retain cursor`() = runBlocking {
        FakeWeibo().use { web ->
            web.respond = { request ->
                json(
                    if (request.url.pathSegments.last() == "UserTweets")
                        xProfilePosts(cursor = "next")
                    else xProfileFixture
                )
            }
            val graph = testGraph(xApi = xProfileApi(web))
            graph.accounts.add(SocialPlatform.X, xProfileSession("7"))
            graph.accounts.add(SocialPlatform.X, xProfileSession("8"))
            val profile = graph.xInteractions.profile("x:8", XProfileUser(handle = "fixture"))
            graph.xInteractions.profile("x:7", profile.user)
            val page = graph.xInteractions.userPosts("x:8", "42", "cursor-from-server")
            assertEquals("next", page.nextCursor)
            assertEquals(
                listOf("UserByScreenName", "UserByRestId", "UserTweets"),
                web.requests.map { it.url.pathSegments.last() },
            )
            assertEquals(
                listOf("csrf-8", "csrf-7", "csrf-8"),
                web.requests.map { it.headers["x-csrf-token"] },
            )
            val variables = parse(web.requests.last().url.queryParameter("variables")!!)
            assertEquals("42", variables["userId"]?.jsonPrimitive?.content)
            assertEquals("cursor-from-server", variables["cursor"]?.jsonPrimitive?.content)
        }
    }
}
