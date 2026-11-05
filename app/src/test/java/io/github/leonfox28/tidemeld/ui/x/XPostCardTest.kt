package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.net.RequestThrottle
import io.github.leonfox28.tidemeld.core.session.StoredSession
import io.github.leonfox28.tidemeld.data.model.Account
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.navigation.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class XPostCardTest {
    @get:Rule val compose = createComposeRule()
    private val web = FakeWeibo()
    private val spec =
        Json.parseToJsonElement(
                """{"operations":{"FavoriteTweet":{"queryId":"fixture"},"CreateTweet":{"queryId":"fixture"},"CreateRetweet":{"queryId":"fixture"}}}"""
            )
            .jsonObject
    private val graph =
        testGraph(web = web, xApi = XWebApi(web.client, spec, RequestThrottle(minIntervalMs = 0)))
    private val post = XPost("42", "作者", "fixture", null, "合成正文", null)

    init {
        runBlocking {
            graph.accounts.add(
                SocialPlatform.X,
                StoredSession(
                    Account("7", "合成账号"),
                    mapOf("x.com" to mapOf("auth_token" to "synthetic", "ct0" to "synthetic")),
                ),
            )
        }
    }

    @After fun close() = web.close()

    @Test
    fun `native card shares acknowledged likes and comments open account detail`() {
        web.respond = { json("""{"data":{"favorite_tweet":"Done"}}""") }
        val navigator = Navigator()
        compose.setContent {
            TestHost(graph, navigator) {
                Column {
                    XPostCard(post, "x:7")
                    XPostCard(post, "x:7")
                }
            }
        }
        compose.onAllNodesWithText("赞 0")[0].performClick()
        compose.waitUntil(5000) {
            compose.onAllNodesWithText("已赞 1").fetchSemanticsNodes().size == 2
        }
        assertEquals(1, web.requests.size)
        compose.onAllNodesWithText("评论 0")[0].performClick()
        assertEquals(Route.XDetail("x:7", "42", post), navigator.backStack.last())
        compose.onNodeWithText("在 X 中查看与互动").assertDoesNotExist()
    }

    @Test
    fun `repost menu does not send until selected and failed comment preserves draft`() {
        web.respond = { json("{}", 500) }
        compose.setContent { TestHost(graph) { XPostCard(post, "x:7") } }
        compose.onNodeWithText("转发 0").performClick()
        compose.onNodeWithText("转发到我的时间线").assertIsDisplayed()
        assertTrue(web.requests.isEmpty())
        compose.onNodeWithText("引用转发").performClick()
        compose.onNode(hasSetTextAction()).performTextInput("合成草稿")
        compose.onNodeWithText("发送").performClick()
        compose.waitUntil(5000) {
            compose.onAllNodesWithText(XWebApi.WRITE_UNCERTAIN).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("合成草稿").assertExists()
        assertEquals(
            "合成草稿",
            graph.xInteractions.drafts[graph.xInteractions.key("x:7", "42") + ":quote"],
        )
        assertEquals(1, web.requests.size)
        compose.onNodeWithText("取消").performClick()
        compose.onNodeWithText("转发 0").assertExists()
    }
}
