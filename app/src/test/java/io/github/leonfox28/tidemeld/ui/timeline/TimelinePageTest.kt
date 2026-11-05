package io.github.leonfox28.tidemeld.ui.timeline

import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import io.github.leonfox28.tidemeld.TidemeldApp
import io.github.leonfox28.tidemeld.support.FakeWeibo
import io.github.leonfox28.tidemeld.support.feedJson
import io.github.leonfox28.tidemeld.support.json
import io.github.leonfox28.tidemeld.support.signedIn
import io.github.leonfox28.tidemeld.support.statusJson
import io.github.leonfox28.tidemeld.support.testGraph
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class TimelinePageTest {
    @get:Rule val compose = createComposeRule()

    private val web = FakeWeibo()

    @After fun tearDown() = web.close()

    private fun status(n: Int) = compose.onNode(hasText("第${n}条"), useUnmergedTree = true)

    private fun shown(n: Int, text: String = "第${n}条") =
        compose.onAllNodes(hasText(text), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun feeds() = web.requests.count { it.url.encodedPath == "/ajax/feed/friendstimeline" }

    @Test
    fun `feed menu filters platforms and X links retain the originating account`() {
        val xJSON =
            """{"data":{"home":{"home_timeline_urt":{"instructions":[{"entries":[{"content":{"itemContent":{"tweet_results":{"result":{"rest_id":"91","core":{"user_results":{"result":{"core":{"name":"X 作者","screen_name":"fixture"}}}},"legacy":{"full_text":"来自X的信息"}}}}}}]}]}}}}"""
        web.respond = {
            if (it.url.host == "api.x.com") json(xJSON)
            else json(feedJson(listOf(statusJson(text = "来自微博的信息"))).toString())
        }
        val spec =
            kotlinx.serialization.json.Json.parseToJsonElement(
                """{"operations":{"HomeLatestTimeline":{"queryId":"fixture","features":{}}}}"""
            ) as kotlinx.serialization.json.JsonObject
        val graph =
            testGraph(
                restored = signedIn,
                web = web,
                xApi =
                    io.github.leonfox28.tidemeld.data.x.XWebApi(
                        web.client,
                        spec,
                        io.github.leonfox28.tidemeld.core.net.RequestThrottle(minIntervalMs = 0),
                    ),
            )
        kotlinx.coroutines.runBlocking {
            graph.accounts.add(
                io.github.leonfox28.tidemeld.core.accounts.SocialPlatform.X,
                io.github.leonfox28.tidemeld.core.session.StoredSession(
                    io.github.leonfox28.tidemeld.data.model.Account("9", "X账号"),
                    mapOf("x.com" to mapOf("auth_token" to "synthetic", "ct0" to "csrf")),
                ),
            )
        }
        val navigator = io.github.leonfox28.tidemeld.ui.navigation.Navigator()
        // A page host records destinations without opening a real WebView.
        compose.setContent {
            io.github.leonfox28.tidemeld.support.TestHost(graph, navigator) {
                TimelinePage(androidx.compose.foundation.layout.PaddingValues())
            }
        }
        compose.waitUntil(5_000) { shown(0, "来自微博的信息") && shown(0, "来自X的信息") }
        compose.onNodeWithContentDescription("选择信息流").performClick()
        compose.onNodeWithText("X", useUnmergedTree = true).performClick()
        compose.waitUntil(5_000) { !shown(0, "来自微博的信息") && shown(0, "来自X的信息") }
        compose.onNodeWithText("评论 0").performClick()
        val route =
            navigator.backStack.last() as io.github.leonfox28.tidemeld.ui.navigation.Route.XDetail
        assertEquals("x:9", route.owner)
        assertEquals("91", route.id)
        compose.onNodeWithContentDescription("选择信息流").performClick()
        compose.onNodeWithText("微博", useUnmergedTree = true).performClick()
        compose.waitUntil(5_000) { shown(0, "来自微博的信息") && !shown(0, "来自X的信息") }
    }

    @Test
    fun `a tap on the open tab scrolls back to the top, the next one refreshes`() {
        web.respond = {
            json(
                feedJson(
                        (1..30).map { statusJson(id = it.toLong(), text = "第${it}条") },
                        maxId = 100,
                    )
                    .toString()
            )
        }
        compose.setContent { TidemeldApp(testGraph(restored = signedIn, web = web)) }
        compose.waitUntil(5_000) { shown(1) }

        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(20)
        status(1).assertDoesNotExist()

        compose.onNodeWithContentDescription("首页").performClick()
        compose.waitUntil(5_000) { shown(1) }
        assertEquals(1, feeds())

        compose.onNodeWithContentDescription("首页").performClick()
        compose.waitUntil(5_000) { feeds() == 2 }
    }

    @Test
    fun `a refresh from the top shows the newest status, not the old first one`() {
        var newest = 30
        web.respond = {
            json(
                feedJson((newest downTo 1).map { statusJson(id = it.toLong(), text = "第${it}条") })
                    .toString()
            )
        }
        compose.setContent { TidemeldApp(testGraph(restored = signedIn, web = web)) }
        compose.waitUntil(5_000) { shown(30) }

        newest = 32
        compose.onNodeWithContentDescription("首页").performClick()
        compose.waitUntil(5_000) { feeds() == 2 }
        compose.waitUntil(5_000) { shown(32) }
    }

    @Test
    fun `pulling to refresh checks notifications, once a minute`() {
        web.respond = {
            if (it.url.encodedPath == "/2/remind/push_count.json") json("""{"cmt":1}""")
            else json(feedJson(listOf(statusJson(text = "首页的一条微博"))).toString())
        }
        val graph = testGraph(restored = signedIn, web = web)
        compose.setContent { TidemeldApp(graph) }
        compose.waitUntil(5_000) { shown(0, "首页的一条微博") }
        fun checks() = web.requests.count { it.url.encodedPath == "/2/remind/push_count.json" }
        // Signing in (or opening the app) checks once.
        compose.waitUntil(5_000) { checks() == 1 }

        compose.onNode(hasScrollToIndexAction()).performTouchInput { swipeDown() }
        compose.waitUntil(5_000) { feeds() == 2 }
        // Within a minute of the last one.
        assertEquals(1, checks())
        assertTrue(graph.unread.state.value.any)
    }
}
