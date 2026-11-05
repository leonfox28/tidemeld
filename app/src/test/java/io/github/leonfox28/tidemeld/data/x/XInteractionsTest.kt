package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.net.*
import io.github.leonfox28.tidemeld.core.session.StoredSession
import io.github.leonfox28.tidemeld.data.model.Account
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.x.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class XInteractionsTest {
    @Test
    fun `native video refresh uses original post source account and video index`() = runBlocking {
        FakeWeibo().use { web ->
            web.respond = {
                json(
                    """
            {"data":{"threaded_conversation_with_injections_v2":{"instructions":[{"entries":[{"content":{"itemContent":{"tweet_results":{"result":{
              "rest_id":"42","core":{"user_results":{"result":{"core":{"screen_name":"fixture"}}}},
              "legacy":{"full_text":"合成内容","extended_entities":{"media":[
                {"type":"video","video_info":{"variants":[{"content_type":"video/mp4","url":"https://media.test/first.mp4"}]}},
                {"type":"animated_gif","video_info":{"variants":[{"content_type":"video/mp4","url":"https://media.test/second.mp4"}]}}
              ]}}
            }}}}}]}]}}}
            """
                )
            }
            val graph = testGraph(xApi = api(web))
            graph.accounts.add(SocialPlatform.X, session("7"))
            graph.accounts.add(SocialPlatform.X, session("8"))
            val request =
                xVideoRequest(
                    graph,
                    "x:7",
                    "42",
                    1,
                    io.github.leonfox28.tidemeld.data.model.VideoInfo(
                        streamUrls = listOf("https://media.test/old.mp4")
                    ),
                )
            assertEquals(
                io.github.leonfox28.tidemeld.core.media.VideoSource(
                    "https://media.test/old.mp4",
                    false,
                ),
                request.resolve(false),
            )
            assertTrue(web.requests.isEmpty())
            assertEquals(
                io.github.leonfox28.tidemeld.core.media.VideoSource(
                    "https://media.test/second.mp4",
                    true,
                ),
                request.resolve(true),
            )
            assertEquals("https://x.com/", request.headers["Referer"])
            assertNull(request.headers["Cookie"])
            val sent = web.requests.single()
            assertEquals("csrf-7", sent.headers["x-csrf-token"])
            assertEquals(
                "42",
                Json.parseToJsonElement(sent.url.queryParameter("variables")!!)
                    .jsonObject["focalTweetId"]
                    ?.jsonPrimitive
                    ?.content,
            )
            graph.accounts.add(SocialPlatform.X, session("7"))
            try {
                request.resolve(true)
                fail("An old account must not refresh media")
            } catch (_: SessionExpiredException) {}
            assertEquals(1, web.requests.size)
        }
    }

    private fun session(id: String) =
        StoredSession(
            Account(id),
            mapOf("x.com" to mapOf("auth_token" to "synthetic-$id", "ct0" to "csrf-$id")),
        )

    private fun api(
        web: FakeWeibo,
        throttle: RequestThrottle = RequestThrottle(minIntervalMs = 0),
    ): XWebApi {
        val operations =
            listOf(
                "TweetDetail",
                "FavoriteTweet",
                "UnfavoriteTweet",
                "CreateRetweet",
                "DeleteRetweet",
                "CreateTweet",
            )
        val spec = buildJsonObject {
            put(
                "operations",
                buildJsonObject {
                    operations.forEach {
                        put(it, buildJsonObject { put("queryId", "fixture-$it") })
                    }
                },
            )
        }
        return XWebApi(web.client, spec, throttle)
    }

    private val post =
        XPost(
            "wrapper",
            "作者",
            "fixture",
            null,
            "合成内容",
            null,
            originalId = "42",
            metrics = XMetrics(likes = 3, reposts = 2, replies = 1),
        )

    private fun body(request: mockwebserver3.RecordedRequest) =
        Json.parseToJsonElement(request.body!!.utf8()).jsonObject

    @Test
    fun `writes use POST original post and scoped credentials with confirmed acknowledgements`() =
        runBlocking {
            FakeWeibo().use { web ->
                web.respond = { request ->
                    when (request.url.pathSegments.last()) {
                        "FavoriteTweet" -> json("""{"data":{"favorite_tweet":"Done"}}""")
                        "UnfavoriteTweet" -> json("""{"data":{"unfavorite_tweet":"Done"}}""")
                        "CreateRetweet" ->
                            json(
                                """{"data":{"create_retweet":{"retweet_results":{"result":{"rest_id":"99"}}}}}"""
                            )
                        "DeleteRetweet" ->
                            json(
                                """{"data":{"unretweet":{"source_tweet_results":{"result":{"rest_id":"42"}}}}}"""
                            )
                        else ->
                            json(
                                """{"data":{"create_tweet":{"tweet_results":{"result":{"rest_id":"100"}}}}}"""
                            )
                    }
                }
                val service = api(web)
                service.like(session("7"), "42", true)
                service.like(session("8"), "42", false)
                service.repost(session("7"), "42", true)
                service.repost(session("7"), "42", false)
                assertEquals("100", service.publish(session("7"), post, " 回复 "))
                service.publish(session("8"), post, "引用", quote = true)
                assertEquals(6, web.requests.size)
                web.requests.forEach {
                    assertEquals("POST", it.method)
                    assertNull(it.url.query)
                    assertTrue(it.headers["Content-Type"]!!.contains("application/json"))
                }
                assertEquals("csrf-8", web.requests[1].headers["x-csrf-token"])
                assertFalse(web.requests[1].headers["Cookie"]!!.contains("synthetic-7"))
                assertEquals(
                    "42",
                    body(web.requests[3])["variables"]!!
                        .jsonObject["source_tweet_id"]!!
                        .jsonPrimitive
                        .content,
                )
                val reply = body(web.requests[4])["variables"]!!.jsonObject
                assertEquals("回复", reply["tweet_text"]!!.jsonPrimitive.content)
                assertEquals(
                    "42",
                    reply["reply"]!!.jsonObject["in_reply_to_tweet_id"]!!.jsonPrimitive.content,
                )
                assertNull(reply["attachment_url"])
                val quote = body(web.requests[5])["variables"]!!.jsonObject
                assertEquals(post.url, quote["attachment_url"]!!.jsonPrimitive.content)
                assertNull(quote["reply"])
            }
        }

    @Test
    fun `server errors partial data and unknown responses never acknowledge or automatically retry`() =
        runBlocking {
            FakeWeibo().use { web ->
                val service = api(web)
                for ((payload, status) in
                    listOf(
                        "{}" to 500,
                        "not-json" to 200,
                        """{"data":{"favorite_tweet":"Done"},"errors":[{"code":226}]}""" to 200,
                        "{}" to 200,
                    )) {
                    web.respond = { json(payload, status) }
                    val before = web.requests.size
                    val error = runCatching {
                        service.like(session("7"), "42", true)
                    }
                        .exceptionOrNull()
                    assertTrue(error is WeiboApiException)
                    assertEquals(before + 1, web.requests.size)
                }
            }
        }

    @Test
    fun `account and original ID isolate state and stale reads cannot undo a confirmed write`() =
        runBlocking {
            FakeWeibo().use { web ->
                web.respond = { json("""{"data":{"favorite_tweet":"Done"}}""") }
                val graph = testGraph(web = web, xApi = api(web))
                graph.accounts.add(SocialPlatform.X, session("7"))
                graph.accounts.add(SocialPlatform.X, session("8"))
                val interactions = graph.xInteractions
                val account = graph.accounts.find("x:7")!!
                val stamp = interactions.readStamp
                interactions.write("x:7", post, XWrite.Like)
                assertTrue(interactions.state("x:7", post.copy(id = "42")).metrics.liked)
                assertEquals(4, interactions.state("x:7", post).metrics.likes)
                assertFalse(interactions.state("x:8", post).metrics.liked)
                interactions.ingest(account, listOf(post), stamp)
                assertTrue(interactions.state("x:7", post).metrics.liked)
                web.respond = { json("{}", 500) }
                assertTrue(runCatching { interactions.write("x:7", post, XWrite.Like) }.isFailure)
                assertTrue(interactions.state("x:7", post).metrics.liked)
                assertFalse(interactions.state("x:7", post).busy)
                interactions.ingest(account, listOf(post), interactions.readStamp)
                assertFalse(interactions.state("x:7", post).metrics.liked)
            }
        }

    @Test
    fun `pending action blocks duplicates and late response cannot alter relogged account`() =
        runBlocking {
            FakeWeibo().use { web ->
                val arrived = CountDownLatch(1)
                val release = CountDownLatch(1)
                web.respond = {
                    arrived.countDown()
                    release.await(5, TimeUnit.SECONDS)
                    json("""{"data":{"favorite_tweet":"Done"}}""")
                }
                val graph = testGraph(web = web, xApi = api(web))
                graph.accounts.add(SocialPlatform.X, session("7"))
                val interactions = graph.xInteractions
                val pending = async { runCatching { interactions.write("x:7", post, XWrite.Like) } }
                yield()
                withContext(Dispatchers.IO) { assertTrue(arrived.await(5, TimeUnit.SECONDS)) }
                assertTrue(interactions.state("x:7", post).busy)
                assertTrue(runCatching { interactions.write("x:7", post, XWrite.Like) }.isFailure)
                graph.accounts.add(SocialPlatform.X, session("7"))
                release.countDown()
                assertTrue(pending.await().isFailure)
                assertFalse(interactions.state("x:7", post).metrics.liked)
                assertEquals(1, web.requests.size)
            }
        }

    @Test
    fun `queued writes check account again before sending`() = runBlocking {
        FakeWeibo().use { web ->
            val throttle = RequestThrottle(maxConcurrent = 1, minIntervalMs = 0)
            throttle.acquire()
            val current = java.util.concurrent.atomic.AtomicBoolean(true)
            val pending = async {
                runCatching {
                    api(web, throttle).like(session("7"), "42", true, isCurrent = current::get)
                }
            }
            yield()
            current.set(false)
            throttle.release()
            assertTrue(pending.await().isFailure)
            assertTrue(web.requests.isEmpty())
        }
    }

    @Test
    fun `auth failure expires only source account`() = runBlocking {
        FakeWeibo().use { web ->
            web.respond = { json("{}", 401) }
            val graph = testGraph(web = web, xApi = api(web))
            graph.accounts.add(SocialPlatform.X, session("7"))
            graph.accounts.add(SocialPlatform.X, session("8"))
            assertTrue(
                runCatching { graph.xInteractions.write("x:7", post, XWrite.Like) }
                    .exceptionOrNull() is SessionExpiredException
            )
            assertTrue(graph.accounts.find("x:7")!!.expired)
            assertFalse(graph.accounts.find("x:8")!!.expired)
        }
    }
}
