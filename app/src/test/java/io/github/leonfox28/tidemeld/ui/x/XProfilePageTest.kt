package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.navigation.*
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class XProfilePageTest {
    @get:Rule val compose = createComposeRule()
    private val web = FakeWeibo()
    private val graph = testGraph(web = web, xApi = xProfileApi(web))

    init {
        runBlocking { graph.accounts.add(SocialPlatform.X, xProfileSession("8")) }
    }

    @After fun close() = web.close()

    private fun awaitText(text: String) =
        compose.waitUntil(5000) {
            compose
                .onAllNodesWithText(text, useUnmergedTree = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }

    @Test
    fun `named profile resolves once then fills shared header and cards`() {
        web.respond = { request ->
            json(
                if (request.url.pathSegments.last() == "UserTweets") xProfilePosts()
                else if (request.url.encodedPath == "/1.1/friendships/show.json")
                    relationshipFixture().replace("\"followed_by\":false", "\"followed_by\":true")
                else xProfileFixture
            )
        }
        val navigator = Navigator()
        compose.setContent {
            TestHost(graph, navigator) { XProfilePage("x:8", XProfileUser(handle = "fixture")) }
        }
        awaitText("合成简介")
        awaitText("合成帖子1")
        compose.onNodeWithText("互相关注", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("帖子已受保护", useUnmergedTree = true).assertExists()
        assertEquals(
            listOf("UserByScreenName", "UserTweets"),
            web.requests
                .filter { it.url.encodedPath.contains("/graphql/") }
                .map { it.url.pathSegments.last() },
        )
        awaitText("取消关注")
        compose.onNodeWithText("合成帖子1", useUnmergedTree = true).performScrollTo().performClick()
        val route = navigator.backStack.last() as Route.XDetail
        assertEquals("x:8", route.owner)
        assertEquals("1", route.id)
    }

    @Test
    fun `failed header retry keeps posts and only refetches the header`() {
        var fail = true
        web.respond = { request ->
            if (request.url.pathSegments.last() == "UserTweets") json(xProfilePosts())
            else if (fail) json("{}", 500) else json(xProfileFixture)
        }
        compose.setContent {
            TestHost(graph) { XProfilePage("x:8", XProfileUser(id = "42", name = "初始名字")) }
        }
        awaitText("合成帖子1")
        compose.waitUntil(5000) {
            compose.onAllNodesWithText("重试").fetchSemanticsNodes().isNotEmpty()
        }
        fail = false
        compose.onNodeWithText("重试").performClick()
        awaitText("合成简介")
        assertEquals(1, web.requests.count { it.url.pathSegments.last() == "UserTweets" })
    }

    @Test
    fun `author opens native profile instead of outer card with source account`() {
        val navigator = Navigator()
        val post = XPost("1", "合成用户", "fixture", null, "合成帖子", null, authorId = "42")
        compose.setContent { TestHost(graph, navigator) { XPostCard(post, "x:8") } }
        compose.onNodeWithText("合成用户", useUnmergedTree = true).performClick()
        assertEquals(Route.XProfile("x:8", post.profileUser), navigator.backStack.last())
        assertTrue(web.requests.isEmpty())
    }

    @Test
    fun `own profile author tap stays on the profile instead of opening the post`() {
        val navigator = Navigator()
        val post = XPost("1", "合成用户", "fixture", null, "合成帖子", null)
        compose.setContent {
            TestHost(graph, navigator) { XPostCard(post, "x:8", profileHandle = "Fixture") }
        }
        compose.onNodeWithText("合成用户", useUnmergedTree = true).performClick()
        assertEquals(listOf(Route.Home), navigator.backStack.toList())
        assertTrue(web.requests.isEmpty())
    }
}
