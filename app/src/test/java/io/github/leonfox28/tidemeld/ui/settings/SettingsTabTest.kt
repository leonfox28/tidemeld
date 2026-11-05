package io.github.leonfox28.tidemeld.ui.settings

import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import io.github.leonfox28.tidemeld.AppGraph
import io.github.leonfox28.tidemeld.TidemeldApp
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.support.FakeWebCookies
import io.github.leonfox28.tidemeld.support.InMemorySessionStorage
import io.github.leonfox28.tidemeld.support.signedIn
import io.github.leonfox28.tidemeld.support.testGraph
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SettingsTabTest {
    @get:Rule val compose = createComposeRule()

    private fun open(graph: AppGraph = testGraph()) {
        compose.setContent { TidemeldApp(graph) }
        compose.onNodeWithContentDescription("设置").performClick()
    }

    private fun scrollTo(text: String) {
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasText(text))
    }

    @Test
    fun `visitors can use settings directly without a profile entry`() {
        open()

        compose.onNodeWithText("主题").assertExists()
        compose.onNodeWithContentDescription("返回").assertDoesNotExist()
        compose.onNodeWithContentDescription("我的主页").assertDoesNotExist()
        scrollTo("账号管理")
        compose.onNodeWithText("账号管理").assertExists()
        compose.onNodeWithText("退出登录").assertDoesNotExist()
    }

    @Test
    fun `says when the session expired in account settings`() {
        val graph = testGraph(restored = signedIn)
        graph.session.expire()
        open(graph)
        scrollTo("账号管理")

        compose.onNodeWithText("账号管理").performClick()
        compose.onNodeWithText("登录已过期").assertExists()
    }

    @Test
    fun `signs out once confirmed without showing a profile card`() {
        val storage = InMemorySessionStorage(signedIn)
        val webCookies = FakeWebCookies(signedIn.cookies)
        val graph =
            testGraph(restored = signedIn, sessionStorage = storage, webCookies = webCookies)
        open(graph)
        compose.onNodeWithText("UID 7").assertDoesNotExist()
        scrollTo("账号管理")
        compose.onNodeWithText("账号管理").performClick()

        compose.onNodeWithText("移除").performClick()
        compose.onNodeWithText("其他账号保持登录。", substring = true).assertExists()
        compose.onNodeWithText("取消").performClick()
        assertTrue(graph.session.state.value is SessionState.SignedIn)

        compose.onNodeWithText("移除").performClick()
        compose.onAllNodes(hasText("移除"))[1].performClick()
        compose.waitForIdle()

        assertEquals(SessionState.SignedOut(), graph.session.state.value)
        assertNull(storage.stored)
        assertTrue(webCookies.cleared)
        compose.onNodeWithText("添加微博账号").assertExists()
    }

    @Test
    fun `the login button opens Weibo's login page and returns to settings`() {
        open()
        scrollTo("账号管理")
        compose.onNodeWithText("账号管理").performClick()
        compose.onNodeWithContentDescription("添加账号").performClick()
        compose.onNodeWithText("微博").performClick()

        compose.onNodeWithText("下方是微博官方登录页面。", substring = true).assertExists()
        compose.onNodeWithText("隐私政策").assertExists()
        compose.onNodeWithContentDescription("关闭").performClick()
        compose.onNodeWithText("选择登录平台").assertExists()
    }
}
