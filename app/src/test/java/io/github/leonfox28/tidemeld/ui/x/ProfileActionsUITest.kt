package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.support.*
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w393dp-h852dp")
class ProfileActionsUITest {
    @get:Rule val compose = createComposeRule()
    private val web = FakeWeibo()
    private val graph = testGraph(web = web, xApi = xProfileApi(web))

    @After fun close() = web.close()

    private fun awaitText(text: String) =
        compose.waitUntil(5000) {
            compose
                .onAllNodesWithText(text, useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }

    @Test
    fun `profile has right side controls menu toggles reposts and block requires confirmation`() {
        runBlocking { graph.accounts.add(SocialPlatform.X, xProfileSession("8")) }
        var reposts = true
        var blocked = false
        web.respond = { request ->
            when (request.url.encodedPath) {
                "/1.1/friendships/show.json" ->
                    json(relationshipFixture(!blocked, blocked, reposts))
                "/1.1/friendships/update.json" -> {
                    reposts = request.form["retweets"] == "true"
                    json("""{"id_str":"42"}""")
                }
                "/1.1/blocks/create.json" -> {
                    blocked = true
                    json("""{"id_str":"42"}""")
                }
                else ->
                    json(
                        if (request.url.pathSegments.last() == "UserTweets") xProfilePosts()
                        else xProfileFixture
                    )
            }
        }
        compose.setContent { TestHost(graph) { XProfilePage("x:8", XProfileUser(id = "42")) } }
        awaitText("取消关注")
        val follow = compose.onNodeWithText("取消关注").fetchSemanticsNode().boundsInRoot
        val more = compose.onNodeWithContentDescription("更多用户操作").fetchSemanticsNode().boundsInRoot
        assertTrue(more.left >= follow.right)
        compose.onNodeWithContentDescription("更多用户操作").performClick()
        compose.onNodeWithText("关闭转帖").performClick()
        compose.waitUntil(5000) {
            web.requests.count { it.method == "GET" && it.url.encodedPath.endsWith("show.json") } >=
                2
        }
        awaitText("取消关注")
        compose.onNodeWithContentDescription("更多用户操作").performClick()
        compose.onNodeWithText("开启转帖").assertExists()
        compose.onNodeWithText("拉黑").performClick()
        compose.onNodeWithText("确定拉黑“合成用户”？这也会解除关注关系。").assertExists()
        assertFalse(web.requests.any { it.url.encodedPath.contains("blocks/create") })
        compose.onAllNodesWithText("拉黑").onLast().performClick()
        awaitText("已拉黑")
        compose.onNodeWithText("取消关注").assertDoesNotExist()
        compose.onNodeWithContentDescription("更多用户操作").performClick()
        compose.onNodeWithText("取消拉黑").assertExists()
        compose.onNodeWithText("开启转帖").assertDoesNotExist()
    }
}
