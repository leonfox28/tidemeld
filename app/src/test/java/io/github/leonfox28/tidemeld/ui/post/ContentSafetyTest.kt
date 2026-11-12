package io.github.leonfox28.tidemeld.ui.post

import android.net.Uri
import androidx.compose.material3.Text
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.leonfox28.tidemeld.TidemeldApp
import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.settings.AppSettings
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.profile.WeiboProfileControls
import io.github.leonfox28.tidemeld.ui.settings.ContentTerms
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ContentSafetyTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun `Weibo comment report opens from long press with the source account`() {
        val graph = testGraph(restored = signedIn)
        val navigator = Navigator()
        val comment =
            io.github.leonfox28.tidemeld.data.model.Comment.tryFromJson(
                commentJson(id = 42, text = "合成评论")
            )!!
        compose.setContent {
            TestHost(graph, navigator) {
                io.github.leonfox28.tidemeld.ui.comments.CommentTile(comment)
            }
        }
        compose.onNodeWithContentDescription("更多评论操作").assertDoesNotExist()
        compose.onNodeWithText("举报").assertDoesNotExist()
        compose.onNodeWithText("合成评论").performTouchInput { longClick() }
        compose.onNodeWithText("举报").performClick()
        val route = navigator.backStack.last() as Route.Report
        assertEquals("weibo:7", route.report.owner)
        assertEquals("42", Uri.parse(route.report.url).getQueryParameter("rid"))
        assertEquals("2", Uri.parse(route.report.url).getQueryParameter("type"))
    }

    @Test
    fun `X comment report opens from long press with its original post and account`() {
        val graph = testGraph()
        runBlocking { graph.accounts.add(SocialPlatform.X, xProfileSession("8")) }
        val navigator = Navigator()
        val post = XPost("42", "合成作者", "fixture", null, "合成回复", null, originalId = "41")
        compose.setContent {
            TestHost(graph, navigator) {
                io.github.leonfox28.tidemeld.ui.x.XCommentTile(post, "x:8")
            }
        }
        compose.onNodeWithContentDescription("更多评论操作").assertDoesNotExist()
        compose.onNodeWithText("举报").assertDoesNotExist()
        compose.onNodeWithText("合成回复").performTouchInput { longClick() }
        compose.onNodeWithText("举报").performClick()
        val route = navigator.backStack.last() as Route.Report
        assertEquals("x:8", route.report.owner)
        assertEquals("https://x.com/fixture/status/41", route.report.url)
    }

    @Test
    fun `consent gates account access and persists explicit acceptance`() {
        FakeWeibo().use { web ->
            val graph = testGraph(settings = AppSettings(), web = web)
            val navigator = Navigator().apply { push(Route.Accounts) }
            compose.setContent { TidemeldApp(graph, navigator) }
            compose.onNodeWithText("同意并继续").performScrollTo().assertExists()
            compose.onNodeWithContentDescription("添加账号").assertDoesNotExist()
            assertTrue(web.requests.isEmpty())
            assertEquals("", graph.settings.settings.value.acceptedTermsVersion)
            compose.onNodeWithText("同意并继续").performClick()
            compose.onNodeWithText("同意并继续").assertDoesNotExist()
            assertEquals(ContentTerms.version, graph.settings.settings.value.acceptedTermsVersion)
            compose.onNodeWithContentDescription("添加账号").assertExists()
        }
    }

    @Test
    fun `confirmed block removes existing content and unblock restores it`() {
        val graph = testGraph()
        compose.setContent {
            TestHost(graph) {
                if (!hideFilteredPost("合成内容", "x:8", listOf("42"))) Text("原有内容")
                if (!hideFilteredPost("合成内容", "x:9", listOf("42"))) Text("另一账号内容")
            }
        }
        compose.onNodeWithText("原有内容").assertExists()
        compose.runOnIdle { graph.settings.recordBlock("x:8", "42", true) }
        compose.onNodeWithText("原有内容").assertDoesNotExist()
        compose.onNodeWithText("另一账号内容").assertExists()
        compose.runOnIdle { graph.settings.recordBlock("x:8", "42", false) }
        compose.onNodeWithText("原有内容").assertExists()
    }

    @Test
    fun `platform confirmed blocks persist and failures never hide content`() = runBlocking {
        FakeWeibo().use { web ->
            var blocked = false
            var reject = false
            web.respond = { request ->
                if (request.method == "POST") {
                    if (reject) json("{}")
                    else {
                        blocked = request.url.encodedPath.endsWith("create.json")
                        json("""{"id_str":"42"}""")
                    }
                } else json(relationshipFixture(blocked = blocked))
            }
            val graph = testGraph(xApi = xProfileApi(web))
            graph.accounts.add(SocialPlatform.X, xProfileSession("8"))
            val store = graph.xInteractions
            val user = XProfileUser("42", "fixture")
            store.refreshRelationship("x:8", "42")
            for (expected in listOf(true, false)) {
                store
                    .relationshipActions("x:8", user, false)!!
                    .more
                    .first { it.id == "block" }
                    .perform()
                assertEquals(
                    expected,
                    ContentBlock.hides(
                        listOf("42"),
                        "x:8",
                        graph.settings.settings.value.blockedUsers,
                    ),
                )
                assertFalse(
                    ContentBlock.hides(
                        listOf("42"),
                        "x:9",
                        graph.settings.settings.value.blockedUsers,
                    )
                )
            }
            reject = true
            val action =
                store.relationshipActions("x:8", user, false)!!.more.first { it.id == "block" }
            assertTrue(runCatching { action.perform() }.isFailure)
            assertTrue(graph.settings.settings.value.blockedUsers.isEmpty())
        }
    }

    @Test
    fun `Weibo blocks update local visibility and stale callback cannot write`() = runBlocking {
        FakeWeibo().use { web ->
            var blocked = false
            web.respond = { request ->
                if (request.method == "POST") {
                    blocked = request.url.encodedPath.endsWith("filterUser")
                    json("""{"ok":1}""")
                } else
                    json(
                        """{"ok":1,"data":{"block":$blocked,"user":{"idstr":"42","screen_name":"合成用户","following":false}}}"""
                    )
            }
            val graph = testGraph(restored = signedIn, web = web)
            val controls = WeiboProfileControls(graph)
            val profile = graph.api.fetchProfile(uid = "42")
            controls.ingest(profile, controls.readStamp)
            for (expected in listOf(true, false)) {
                controls.actions(profile)!!.more.first { it.id == "block" }.perform()
                assertEquals(
                    expected,
                    ContentBlock.hides(
                        listOf("42"),
                        "weibo:7",
                        graph.settings.settings.value.blockedUsers,
                    ),
                )
            }
            val stale = controls.actions(profile)!!.more.first { it.id == "block" }
            graph.accounts.add(SocialPlatform.Weibo, signedIn)
            val before = web.requests.size
            assertTrue(runCatching { stale.perform() }.isFailure)
            assertEquals(before, web.requests.size)
            assertTrue(graph.settings.settings.value.blockedUsers.isEmpty())
        }
    }

    @Test
    fun `report destinations preserve full string identifiers`() {
        for (kind in WeiboReportKind.entries) {
            val uri = Uri.parse(weiboReportUrl("9007199254740993123", kind))
            assertEquals("service.account.weibo.com", uri.host)
            assertEquals("9007199254740993123", uri.getQueryParameter("rid"))
            assertEquals(kind.value, uri.getQueryParameter("type"))
        }
    }
}
