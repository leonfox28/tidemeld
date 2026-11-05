package io.github.leonfox28.tidemeld

import io.github.leonfox28.tidemeld.core.accounts.*
import io.github.leonfox28.tidemeld.core.net.*
import io.github.leonfox28.tidemeld.core.session.StoredSession
import io.github.leonfox28.tidemeld.data.model.*
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.timeline.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import kotlinx.serialization.json.*
import mockwebserver3.MockResponse
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class SocialAccountsTest {
    private fun session(id: String, host: String = "weibo.com") =
        StoredSession(
            Account(id, "账号$id"),
            mapOf(
                host to
                    if (host == "x.com") mapOf("auth_token" to "synthetic-$id", "ct0" to "csrf-$id")
                    else mapOf("SUB" to "synthetic-$id")
            ),
        )

    @Test
    fun `legacy account migrates and multiple identities survive switching and selective removal`() =
        runTest {
            val web =
                FakeWebCookies(
                    mapOf(
                        "weibo.com" to mapOf("SUB" to "synthetic-8"),
                        "x.com" to mapOf("auth_token" to "synthetic-7"),
                    )
                )
            val graph =
                testGraph(restored = session("7"), webCookies = web, scope = backgroundScope)
            assertEquals(listOf("weibo:7"), graph.accounts.accounts.value.map { it.key })
            graph.accounts.add(SocialPlatform.Weibo, session("8"))
            graph.accounts.add(SocialPlatform.X, session("7", "x.com"))
            runCurrent()
            assertEquals(
                setOf("weibo:7", "weibo:8", "x:7"),
                graph.accounts.accounts.value.map { it.key }.toSet(),
            )
            assertTrue(graph.accounts.useWeibo("weibo:7"))
            assertEquals("synthetic-7", graph.session.jar.value("weibo.com", "SUB"))
            graph.accounts.remove("weibo:8")
            runCurrent()
            assertEquals("synthetic-7", web.cookies("https://x.com/")["auth_token"])
            assertEquals(
                setOf("weibo:7", "x:7"),
                graph.accounts.accounts.value.map { it.key }.toSet(),
            )
            graph.accounts.add(
                SocialPlatform.Weibo,
                session("7").copy(cookies = mapOf("weibo.com" to mapOf("SUB" to "fresh"))),
            )
            assertEquals("fresh", graph.session.jar.value("weibo.com", "SUB"))
            assertEquals(2, graph.accounts.accounts.value.size)
        }

    @Test
    fun `web pages select their account without changing another platform or reviving expired accounts`() =
        runTest {
            val web = FakeWebCookies(mapOf("weibo.com" to mapOf("SUB" to "synthetic-7")))
            val graph =
                testGraph(restored = session("7"), webCookies = web, scope = backgroundScope)
            graph.accounts.add(SocialPlatform.X, session("8", "x.com"))
            graph.accounts.add(SocialPlatform.X, session("9", "x.com"))
            graph.accounts.prepareBrowser("x:8")
            assertEquals("synthetic-8", web.cookies("https://x.com/")["auth_token"])
            graph.accounts.prepareBrowser("x:9")
            assertEquals("synthetic-9", web.cookies("https://x.com/")["auth_token"])
            assertEquals("synthetic-7", web.cookies("https://weibo.com/")["SUB"])
            graph.accounts.expire("weibo:7")
            graph.session.jar.replaceAll(mapOf("weibo.com" to mapOf("SUB" to "rotated")))
            runCurrent()
            assertTrue(graph.accounts.find("weibo:7")!!.expired)
            assertFalse(graph.accounts.useWeibo("weibo:7"))
            graph.accounts.remove("x:8")
            assertEquals("synthetic-9", web.cookies("https://x.com/")["auth_token"])
        }

    @Test
    fun `expired vault credentials remain expired after restoring a legacy session`() = runTest {
        val graph = testGraph(restored = session("7"), scope = backgroundScope)
        val saved = SocialAccount(SocialPlatform.Weibo, session("7"), expired = true)
        val vault = MemoryAccountStorage()
        val accounts =
            AccountManager(listOf(saved), vault, graph.session, graph.webCookies, backgroundScope)
        runCurrent()
        assertTrue(accounts.find("weibo:7")!!.expired)
        assertTrue(
            graph.session.state.value
                is io.github.leonfox28.tidemeld.core.session.SessionState.SignedOut
        )
    }

    @Test
    fun `account contexts send their own cookies even when the selected account changes`() =
        runTest {
            FakeWeibo().use { web ->
                web.respond = { json(feedJson(emptyList()).toString()) }
                val graph = testGraph(restored = session("7"), web = web, scope = backgroundScope)
                graph.accounts.add(SocialPlatform.Weibo, session("8"))
                val first = graph.forAccount("weibo:7")!!
                val second = graph.forAccount("weibo:8")!!
                first.api.fetchHomeTimeline("7")
                second.api.fetchHomeTimeline("8")
                val cookies = web.requests.map { it.headers["Cookie"] }
                assertEquals(listOf("SUB=synthetic-7", "SUB=synthetic-8"), cookies)
                graph.accounts.add(
                    SocialPlatform.Weibo,
                    session("7").copy(cookies = mapOf("weibo.com" to mapOf("SUB" to "fresh"))),
                )
                first.session.jar.replaceAll(mapOf("weibo.com" to mapOf("SUB" to "stale")))
                runCurrent()
                assertEquals(
                    "fresh",
                    graph.accounts.find("weibo:7")!!.session.cookies["weibo.com"]!!["SUB"],
                )
            }
        }

    @Test
    fun `aggregation sorts and deduplicates while retaining per-account cursors and failures`() =
        runTest {
            val graph = testGraph(restored = session("7"), scope = backgroundScope)
            graph.accounts.add(SocialPlatform.Weibo, session("8"))
            graph.accounts.add(SocialPlatform.X, session("9", "x.com"))
            runCurrent()
            val calls = mutableListOf<Pair<String, String?>>()
            var xFails = true
            val feed =
                SocialFeedController(graph.accounts, backgroundScope) { account, cursor ->
                    calls += account.key to cursor
                    if (account.platform == SocialPlatform.X) {
                        if (xFails) throw NetworkException()
                        Paged(
                            listOf(
                                FeedPost.X(
                                    account.key,
                                    XPost(
                                        "1",
                                        "X 作者",
                                        "fixture",
                                        null,
                                        "X 内容",
                                        Instant.ofEpochSecond(30),
                                    ),
                                )
                            )
                        )
                    } else {
                        val id = if (cursor == null) "1" else account.session.account.uid
                        Paged(
                            listOf(
                                FeedPost.Weibo(
                                    account.key,
                                    Status(
                                        id,
                                        createdAt =
                                            Instant.ofEpochSecond(if (cursor == null) 20 else 10),
                                    ),
                                )
                            ),
                            if (cursor == null) "cursor-${account.key}" else null,
                        )
                    }
                }
            feed.select(FeedSelection.All)
            runCurrent()
            assertEquals(listOf("weibo:1"), feed.state.value.items.map { it.key })
            assertEquals(setOf("x:9"), feed.state.value.errors.keys)
            feed.loadMore()
            runCurrent()
            assertTrue(calls.contains("weibo:7" to "cursor-weibo:7"))
            assertTrue(calls.contains("weibo:8" to "cursor-weibo:8"))
            val beforeRetry = calls.size
            xFails = false
            feed.retry()
            runCurrent()
            assertEquals(listOf("x:9" to null), calls.drop(beforeRetry))
            assertEquals(
                listOf("x:1", "weibo:1", "weibo:7", "weibo:8"),
                feed.state.value.items.map { it.key },
            )
            feed.select(FeedSelection.X)
            runCurrent()
            assertEquals(listOf("x:1"), feed.state.value.items.map { it.key })
            graph.accounts.remove("x:9")
            runCurrent()
            assertTrue(feed.state.value.items.isEmpty())
        }

    @Test
    fun `a removed account cannot reinsert a delayed page`() = runTest {
        val graph = testGraph(restored = session("7"), scope = backgroundScope)
        val pending = CompletableDeferred<Unit>()
        val feed =
            SocialFeedController(graph.accounts, backgroundScope) { account, _ ->
                withContext(NonCancellable) { pending.await() }
                Paged(listOf(FeedPost.Weibo(account.key, Status("1"))))
            }
        feed.select(FeedSelection.All)
        runCurrent()
        graph.accounts.remove("weibo:7")
        runCurrent()
        pending.complete(Unit)
        runCurrent()
        assertTrue(feed.state.value.items.isEmpty())
    }

    @Test
    fun `X requests stay scoped and do not follow credential-bearing redirects`() = runTest {
        FakeWeibo().use { web ->
            val spec =
                Json.parseToJsonElement(
                        """{"operations":{"HomeLatestTimeline":{"queryId":"fixture","features":{}}}}"""
                    )
                    .jsonObject
            val api = XWebApi(web.client, spec, RequestThrottle(minIntervalMs = 0))
            web.respond = {
                MockResponse.Builder()
                    .code(302)
                    .addHeader("Location", "https://example.com/stolen")
                    .build()
            }
            try {
                api.timeline(session("9", "x.com"), null)
                fail("redirect must fail")
            } catch (_: WeiboApiException) {}
            assertEquals(1, web.requests.size)
            assertEquals("api.x.com", web.requests.single().url.host)
            assertEquals("csrf-9", web.requests.single().headers["x-csrf-token"])
            assertFalse(web.requests.single().headers["Cookie"].orEmpty().contains("SUB="))
            assertTrue(
                web.requests
                    .single()
                    .url
                    .queryParameter("variables")!!
                    .contains("includePromotedContent")
            )
        }
    }
}
