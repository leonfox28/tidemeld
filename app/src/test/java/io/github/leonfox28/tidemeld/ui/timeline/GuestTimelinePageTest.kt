package io.github.leonfox28.tidemeld.ui.timeline

import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.leonfox28.tidemeld.TidemeldApp
import io.github.leonfox28.tidemeld.core.net.RequestThrottle
import io.github.leonfox28.tidemeld.core.net.WeiboCookieJar
import io.github.leonfox28.tidemeld.core.net.WeiboHttp
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.data.api.GuestWeiboApi
import io.github.leonfox28.tidemeld.support.FakeWeibo
import io.github.leonfox28.tidemeld.support.feedJson
import io.github.leonfox28.tidemeld.support.homePage
import io.github.leonfox28.tidemeld.support.json
import io.github.leonfox28.tidemeld.support.signedIn
import io.github.leonfox28.tidemeld.support.statusJson
import io.github.leonfox28.tidemeld.support.testGraph
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class GuestTimelinePageTest {
    @get:Rule val compose = createComposeRule()
    private val web = FakeWeibo()

    @After fun tearDown() = web.close()

    @Test
    fun `signing in switches to the following feed and signing out restores public posts`() {
        web.respond = {
            when (it.url.encodedPath) {
                "/" -> homePage(uid = 7)
                "/api/config" -> json("""{"ok":1,"data":{"login":false}}""")
                "/api/container/getIndex" ->
                    json(
                        """{"ok":1,"data":{"cards":[{"card_type":9,"mblog":{"id":"11","text":"游客公开示例"}}]}}"""
                    )
                "/ajax/feed/friendstimeline" ->
                    json(feedJson(listOf(statusJson(text = "关注动态示例"))).toString())
                "/ajax/profile/info" ->
                    json(
                        """{"ok":1,"data":{"user":{"id":"7","screen_name":"本人示例","avatar_large":"https://example.com/avatar.jpg"}}}"""
                    )
                else -> json("{}")
            }
        }
        val jar = WeiboCookieJar()
        val guest =
            GuestWeiboApi(
                WeiboHttp.create(web.client, jar, RequestThrottle(minIntervalMs = 0)),
                jar,
            ) {
                mapOf(WeiboCookieJar.MOBILE to mapOf("SUB" to "visitor"))
            }
        val graph = testGraph(web = web, guestApi = guest)
        val navigator = Navigator()
        compose.setContent { TidemeldApp(graph, navigator) }
        fun awaitText(text: String) =
            compose.waitUntil(5_000) {
                compose
                    .onAllNodes(androidx.compose.ui.test.hasText(text), useUnmergedTree = true)
                    .fetchSemanticsNodes()
                    .isNotEmpty()
            }
        awaitText("游客公开示例")
        compose.onNodeWithContentDescription("账号管理").assertExists()
        compose.onNodeWithContentDescription("通知").assertDoesNotExist()
        runBlocking { graph.session.completeLogin(signedIn.cookies) }
        awaitText("关注动态示例")
        compose.onNodeWithText("游客浏览 · 公开微博").assertDoesNotExist()
        compose.onNodeWithContentDescription("账号管理").performClick()
        assertEquals(Route.Accounts, navigator.backStack.last())
        compose.runOnIdle { navigator.pop() }
        compose.onNodeWithContentDescription("通知").performClick()
        runBlocking { graph.session.logout() }
        awaitText("游客公开示例")
        compose.onNodeWithText("游客浏览 · 公开微博").assertDoesNotExist()
        compose.onNodeWithContentDescription("账号管理").assertExists()
        compose.onNodeWithContentDescription("我的主页").assertDoesNotExist()
        compose.onNodeWithContentDescription("通知").assertDoesNotExist()
        compose.onNodeWithContentDescription("首页").assertIsSelected()
        assertEquals(1, web.requests.count { it.url.encodedPath == "/ajax/feed/friendstimeline" })
    }

    @Test
    fun `guest home renders a native list and liking opens login without a write`() {
        web.respond = {
            json(
                if (it.url.encodedPath == "/api/config") """{"ok":1,"data":{"login":false}}"""
                else
                    """{"ok":1,"data":{"cards":[{"card_type":9,"mblog":{"id":"11","user":{"id":1,"screen_name":"示例作者"},"text":"原生游客微博示例"}}]}}"""
            )
        }
        val jar = WeiboCookieJar()
        val guest =
            GuestWeiboApi(
                WeiboHttp.create(web.client, jar, RequestThrottle(minIntervalMs = 0)),
                jar,
            ) {
                mapOf(WeiboCookieJar.MOBILE to mapOf("SUB" to "visitor"))
            }
        val graph = testGraph(web = web, guestApi = guest)
        val navigator = Navigator()
        compose.setContent { TidemeldApp(graph, navigator) }
        compose.waitUntil(5_000) {
            compose
                .onAllNodes(androidx.compose.ui.test.hasText("原生游客微博示例"), useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.onNode(hasScrollToIndexAction()).assertExists()
        compose.onNodeWithText("游客浏览 · 公开微博").assertDoesNotExist()
        compose.onNodeWithText("登录查看更多").assertExists()
        compose.onNodeWithContentDescription("账号管理").performClick()
        assertEquals(Route.Accounts, navigator.backStack.last())
        compose.runOnIdle { navigator.pop() }
        compose.onNodeWithText("赞").performClick()
        assertEquals(Route.Login, navigator.backStack.last())
        assertEquals(SessionState.SignedOut(), graph.session.state.value)
        assertEquals(
            listOf("/api/config", "/api/container/getIndex"),
            web.requests.map { it.url.encodedPath },
        )
        assertTrue(web.requests.all { it.method == "GET" })
    }
}
