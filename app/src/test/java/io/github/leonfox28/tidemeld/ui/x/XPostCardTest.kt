package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.net.RequestThrottle
import io.github.leonfox28.tidemeld.core.paging.ListLoad
import io.github.leonfox28.tidemeld.core.session.StoredSession
import io.github.leonfox28.tidemeld.data.model.Account
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.navigation.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
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
                """{"operations":{"TweetDetail":{"queryId":"fixture"},"FavoriteTweet":{"queryId":"fixture"},"CreateTweet":{"queryId":"fixture"},"CreateRetweet":{"queryId":"fixture"}}}"""
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
    fun `compact comment replies to its own original post with its source account`() {
        web.respond = {
            json("""{"data":{"create_tweet":{"tweet_results":{"result":{"rest_id":"100"}}}}}""")
        }
        val comment = post.copy(id = "wrapper", originalId = "70", replyTo = "42")
        var sent = 0
        compose.setContent { TestHost(graph) { XCommentTile(comment, "x:7", onSent = { sent++ }) } }
        compose.onNodeWithContentDescription("转发").assertDoesNotExist()
        compose.onNodeWithText("合成正文").performClick()
        assertTrue(web.requests.isEmpty())
        compose.onNode(hasSetTextAction()).performTextInput("合成回复")
        compose.onNodeWithText("发送").performClick()
        compose.waitUntil(5000) { sent == 1 }
        val request = web.requests.single()
        val variables =
            Json.parseToJsonElement(request.body!!.utf8()).jsonObject["variables"]!!.jsonObject
        assertEquals(
            "70",
            variables["reply"]!!.jsonObject["in_reply_to_tweet_id"]!!.jsonPrimitive.content,
        )
        assertEquals("synthetic", request.headers["x-csrf-token"])
    }

    @Test
    fun `comment thread preview opens the reply using its original identity`() {
        val comment = post.copy(id = "wrapper", originalId = "70", metrics = XMetrics(replies = 3))
        val child = post.copy(id = "71", originalId = "71", text = "下级回复", replyTo = "70")
        val navigator = Navigator()
        compose.setContent {
            TestHost(graph, navigator) {
                XCommentTile(comment, "x:7", authorHandle = "fixture", preview = listOf(child))
            }
        }
        compose.onNodeWithText("博主", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("@作者：下级回复", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("共3条回复 >").performClick()
        assertEquals(Route.XDetail("x:7", "70", comment), navigator.backStack.last())
        assertTrue(web.requests.isEmpty())
    }

    @Test
    fun `detail nests lower replies in previews instead of additional feed cards`() {
        fun entry(id: String, parent: String, text: String) =
            """{"content":{"itemContent":{"tweet_results":{"result":{"rest_id":"$id","core":{"user_results":{"result":{"core":{"name":"作者","screen_name":"fixture"}}}},"legacy":{"full_text":"$text","in_reply_to_status_id_str":"$parent","reply_count":1}}}}}}"""
        web.respond = {
            json(
                """{"data":{"threaded_conversation_with_injections_v2":{"instructions":[{"entries":[${entry("72", "71", "二级回复")},${entry("71", "42", "一级回复")}]}]}}}"""
            )
        }
        compose.setContent { TestHost(graph) { XDetailPage("x:7", "42", post) } }
        compose.waitUntil(5000) {
            compose
                .onAllNodesWithText("一级回复", useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.onNodeWithText("@作者：二级回复", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("二级回复", useUnmergedTree = true).assertDoesNotExist()
        compose
            .onAllNodesWithContentDescription("来源：X", useUnmergedTree = true)
            .assertCountEquals(1)
    }

    private fun contextPage(
        entries: List<Triple<String, String?, String>>,
        cursor: String? = null,
    ): String {
        val rows =
            entries
                .map { (id, parent, body) ->
                    Json.parseToJsonElement(
                        """{"content":{"itemContent":{"tweet_results":{"result":{"rest_id":"$id","core":{"user_results":{"result":{"core":{"name":"作者","screen_name":"fixture"}}}},"legacy":{"full_text":${JsonPrimitive(body)},"in_reply_to_status_id_str":${parent?.let(::JsonPrimitive) ?: JsonNull}}}}}}}"""
                    )
                }
                .toMutableList()
        if (cursor != null)
            rows +=
                Json.parseToJsonElement("""{"content":{"cursorType":"Bottom","value":"$cursor"}}""")
        return """{"data":{"threaded_conversation_with_injections_v2":{"instructions":[{"entries":${JsonArray(rows)}}]}}}"""
    }

    @Test
    fun `reply detail focuses the current post and scrolling up reveals native context without prefetch`() {
        val parentText = "合成上文\n".repeat(40)
        web.respond = {
            json(
                contextPage(
                    listOf(Triple("7", null, parentText), Triple("42", "7", "当前回复")),
                    "next",
                )
            )
        }
        val navigator = Navigator()
        compose.setContent {
            TestHost(graph, navigator) { XDetailPage("x:7", "42", post.copy(repostedBy = "合成转发者")) }
        }
        compose.waitUntil(5000) {
            compose
                .onAllNodesWithText("当前回复", useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.waitForIdle()
        compose.onNodeWithText("当前回复", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("合成转发者 转发", useUnmergedTree = true).assertExists()
        val listTop = compose.onNode(hasScrollToIndexAction()).fetchSemanticsNode().boundsInRoot.top
        val authorTop =
            compose
                .onNodeWithText("合成转发者 转发", useUnmergedTree = true)
                .fetchSemanticsNode()
                .boundsInRoot
                .top
        assertTrue(
            "The focal post should start near the top even with no comments",
            authorTop - listTop < 80,
        )
        assertEquals(1, web.requests.size)
        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(0)
        compose
            .onNodeWithText(parentText, useUnmergedTree = true)
            .assertIsDisplayed()
            .performClick()
        val opened = navigator.backStack.last() as Route.XDetail
        assertEquals("7", opened.id)
        assertEquals("x:7", opened.owner)
    }

    @Test
    fun `comment pagination keeps context and refresh replaces it`() = runBlocking {
        val first =
            contextPage(listOf(Triple("7", null, "合成上文"), Triple("42", "7", "当前回复")), "next")
        val more = contextPage(listOf(Triple("43", "42", "下级回复")))
        web.respond = { request ->
            json(
                if (
                    Json.parseToJsonElement(request.url.queryParameter("variables")!!)
                        .jsonObject["cursor"] == null
                )
                    first
                else more
            )
        }
        val controller =
            XDetailController(
                graph.xInteractions,
                "x:7",
                "42",
                post.copy(repostedBy = "合成转发者"),
                this,
            )
        controller.start()
        withTimeout(5000) { controller.state.first { it is ListLoad.Ready } }
        assertEquals(listOf("7"), controller.ancestors.value.map { it.originalId })
        controller.loadMore()
        assertEquals(listOf("7"), controller.ancestors.value.map { it.originalId })
        assertEquals("当前回复", controller.post.value?.text)
        assertEquals("合成转发者", controller.post.value?.repostedBy)
        assertEquals(2, web.requests.size)
        web.respond = { json(contextPage(listOf(Triple("42", "missing", "更新后的回复")))) }
        controller.refresh()
        assertTrue(controller.ancestors.value.isEmpty())
        assertEquals("更新后的回复", controller.post.value?.text)
        assertEquals("合成转发者", controller.post.value?.repostedBy)
    }

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
        compose.onAllNodesWithContentDescription("赞")[0].performClick()
        compose.waitUntil(5000) {
            compose.onAllNodesWithContentDescription("赞 1").fetchSemanticsNodes().size == 2
        }
        assertEquals(1, web.requests.size)
        compose.onAllNodesWithContentDescription("评论")[0].performClick()
        assertEquals(Route.XDetail("x:7", "42", post), navigator.backStack.last())
        compose.onNodeWithText("在 X 中查看与互动").assertDoesNotExist()
    }

    @Test
    fun `repost menu does not send until selected and failed comment preserves draft`() {
        web.respond = { json("{}", 500) }
        compose.setContent { TestHost(graph) { XPostCard(post, "x:7") } }
        compose.onNodeWithContentDescription("转发").performClick()
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
            graph.xInteractions.drafts[graph.xInteractions.key("x:7", "42") + ":quote"]?.text,
        )
        assertEquals(1, web.requests.size)
        compose.onNodeWithContentDescription("添加图片").assertDoesNotExist()
    }
}
