package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.errors.AppFailure
import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.social.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

internal fun relationshipFixture(
    following: Boolean = true,
    blocked: Boolean = false,
    reposts: Boolean = true,
    requested: Boolean = false,
    source: String = "8",
) =
    """{"relationship":{"source":{"id_str":"$source","following":$following,"followed_by":false,"following_requested":$requested,"blocking":$blocked,"want_retweets":$reposts},"target":{"id_str":"42"}}}"""

@RunWith(RobolectricTestRunner::class)
class ProfileRelationshipTest {
    @Test
    fun `X writes use selected account forms and read back relationship without replay`() =
        runBlocking {
            FakeWeibo().use { web ->
                var following = false
                var blocked = false
                var reposts = true
                var requested = false
                web.respond = { request ->
                    if (request.method == "POST") {
                        when (request.url.encodedPath) {
                            "/1.1/friendships/create.json" -> requested = true
                            "/1.1/friendships/destroy.json" -> {
                                following = false
                                requested = false
                            }
                            "/1.1/blocks/create.json" -> {
                                blocked = true
                                following = false
                            }
                            "/1.1/blocks/destroy.json" -> blocked = false
                            "/1.1/friendships/update.json" ->
                                reposts = request.form["retweets"] == "true"
                        }
                        json("""{"id_str":"42"}""")
                    } else json(relationshipFixture(following, blocked, reposts, requested))
                }
                val api = xProfileApi(web)
                val session = xProfileSession("8")
                assertTrue(
                    api.changeRelationship(session, "42", XUserAction.Follow(true)).requested
                )
                assertFalse(
                    api.changeRelationship(session, "42", XUserAction.Follow(false)).requested
                )
                following = true
                assertFalse(
                    api.changeRelationship(session, "42", XUserAction.Reposts(false)).showsReposts!!
                )
                assertTrue(
                    api.changeRelationship(session, "42", XUserAction.Reposts(true)).showsReposts!!
                )
                assertTrue(api.changeRelationship(session, "42", XUserAction.Block(true)).blocking)
                assertFalse(
                    api.changeRelationship(session, "42", XUserAction.Block(false)).blocking
                )
                assertEquals(6, web.requests.count { it.method == "POST" })
                assertTrue(web.requests.all { it.headers["x-csrf-token"] == "csrf-8" })
                assertTrue(
                    web.requests
                        .filter { it.method == "POST" }
                        .all {
                            it.form["user_id"] == "42" &&
                                it.headers["Content-Type"]!!.startsWith(
                                    "application/x-www-form-urlencoded"
                                )
                        }
                )
                assertTrue(
                    web.requests
                        .filter { it.method == "GET" }
                        .all {
                            it.url.queryParameter("source_id") == "8" &&
                                it.url.queryParameter("target_id") == "42"
                        }
                )
            }
        }

    @Test
    fun `unconfirmed write requires refresh and stale account callback never sends`() =
        runBlocking {
            FakeWeibo().use { web ->
                web.respond = {
                    if (it.method == "POST") json("{}") else json(relationshipFixture())
                }
                val graph = testGraph(xApi = xProfileApi(web))
                graph.accounts.add(SocialPlatform.X, xProfileSession("8"))
                graph.xInteractions.refreshRelationship("x:8", "42")
                val user = XProfileUser("42", "fixture")
                val action = graph.xInteractions.relationshipActions("x:8", user, false)!!.primary!!
                assertTrue(runCatching { action.perform() }.exceptionOrNull() is WeiboApiException)
                val refresh =
                    graph.xInteractions.relationshipActions("x:8", user, false)!!.primary!!
                assertEquals("刷新状态", refresh.title)
                assertTrue(runCatching { action.perform() }.exceptionOrNull() is AppFailure)
                assertEquals(1, web.requests.count { it.method == "POST" })
                refresh.perform()
                val stale = graph.xInteractions.relationshipActions("x:8", user, false)!!.primary!!
                graph.accounts.add(SocialPlatform.X, xProfileSession("8"))
                assertTrue(runCatching { stale.perform() }.exceptionOrNull() is AppFailure)
                assertEquals(1, web.requests.count { it.method == "POST" })
                assertNull(graph.xInteractions.relationshipActions("x:8", XProfileUser("8"), false))
            }
        }

    @Test
    fun `late reads and repeated taps cannot replace a relationship write`() = runBlocking {
        val store = ProfileRelationships()
        val before = ProfileRelationship(false, blocking = false)
        val after = before.copy(following = true)
        store.ingest("x:8:1:42", before, store.readStamp)
        val started = store.readStamp
        val release = CompletableDeferred<Unit>()
        var sends = 0
        val write =
            launch(start = CoroutineStart.UNDISPATCHED) {
                store.perform("x:8:1:42", before, { true }) {
                    sends++
                    release.await()
                    after
                }
            }
        store.perform("x:8:1:42", before, { true }) {
            sends++
            before
        }
        store.ingest("x:8:1:42", before, started)
        assertTrue(store.loadedState("x:8:1:42")!!.busy)
        release.complete(Unit)
        write.join()
        store.ingest("x:8:1:42", before, started)
        assertEquals(after, store.loadedState("x:8:1:42")!!.value)
        assertNull(store.loadedState("x:9:1:42"))
        assertEquals(1, sends)
    }

    @Test
    fun `Weibo follows and blocks use actual web endpoint fields and verify result`() =
        runBlocking {
            FakeWeibo().use { web ->
                var following = false
                var blocking = false
                web.respond = { request ->
                    if (request.method == "POST") {
                        when (request.url.encodedPath) {
                            "/ajax/friendships/create" -> following = true
                            "/ajax/friendships/destory" -> following = false
                            "/ajax/statuses/filterUser" -> {
                                blocking = true
                                following = false
                            }
                            "/ajax/statuses/deleteFilters" -> blocking = false
                        }
                        json("""{"ok":1}""")
                    } else
                        json(
                            """{"ok":1,"data":{"block":$blocking,"user":{"idstr":"42","screen_name":"合成用户","following":$following}}}"""
                        )
                }
                val api = web.api()
                assertTrue(api.changeUserRelationship("42", following = true).following)
                assertFalse(api.changeUserRelationship("42", following = false).following)
                assertTrue(api.changeUserRelationship("42", blocking = true).blocking)
                assertFalse(api.changeUserRelationship("42", blocking = false).blocking)
                val writes = web.requests.filter { it.method == "POST" }
                assertEquals(mapOf("friend_uid" to "42"), writes[0].form)
                assertEquals(mapOf("uid" to "42"), writes[1].form)
                assertEquals(
                    mapOf("uid" to "42", "status" to "1", "interact" to "1", "follow" to "1"),
                    writes[2].form,
                )
                assertTrue(
                    runCatching {
                        api.changeUserRelationship(
                            "42",
                            following = true,
                            isCurrent = { false },
                        )
                    }
                        .isFailure
                )
                assertEquals(4, web.requests.count { it.method == "POST" })
            }
        }
}
