package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import io.github.leonfox28.tidemeld.core.errors.AppFailure
import io.github.leonfox28.tidemeld.core.errors.UserFacingFailure
import io.github.leonfox28.tidemeld.support.TestHost
import io.github.leonfox28.tidemeld.ui.interactions.CommentDraft
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.post.PostComposer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
class SharedPresentationTest {
    @get:Rule val compose = createComposeRule()

    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun `X post links keep the source account and do not open their containing card`() {
        val navigator = Navigator()
        var cardOpens = 0
        val url = "https://x.com/fixture/status/42"
        compose.setContent {
            TestHost(navigator = navigator) {
                Column(Modifier.clickable { cardOpens++ }) { XPostText(url, "x:other") }
            }
        }
        val label = compose.onNodeWithText(url, useUnmergedTree = true)
        val layouts = mutableListOf<TextLayoutResult>()
        label.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val glyph = layouts.single().getBoundingBox(0).center
        label.performTouchInput { click(glyph) }
        compose.waitForIdle()
        assertEquals(Route.XDetail("x:other", "42", null), navigator.backStack.last())
        assertEquals(0, cardOpens)
    }

    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun `X mentions open the source account profile without opening the containing card`() {
        val navigator = Navigator()
        var cardOpens = 0
        compose.setContent {
            TestHost(navigator = navigator) {
                Column(Modifier.clickable { cardOpens++ }) { XPostText("@fixture", "x:other") }
            }
        }
        val label = compose.onNodeWithText("@fixture", useUnmergedTree = true)
        val layouts = mutableListOf<TextLayoutResult>()
        label.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        label.performTouchInput { click(layouts.single().getBoundingBox(0).center) }
        compose.waitForIdle()
        assertEquals(
            Route.XProfile(
                "x:other",
                io.github.leonfox28.tidemeld.data.x.XProfileUser(handle = "fixture"),
            ),
            navigator.backStack.last(),
        )
        assertEquals(0, cardOpens)
    }

    @Test
    fun `the shared editor retains an independent platform failure and its draft until retry succeeds`() {
        class OtherFailure : Exception(), UserFacingFailure {
            override val appFailure = AppFailure("合成平台暂时不可用")
        }
        val drafts = mutableMapOf<String, CommentDraft>()
        var attempts = 0
        var sent = false
        compose.setContent {
            TestHost {
                PostComposer(
                    "写回复",
                    drafts,
                    "other:account:42",
                    send = { text, _ ->
                        assertEquals("合成回复", text)
                        if (++attempts == 1) throw OtherFailure()
                    },
                    close = { sent = it == true },
                )
            }
        }
        compose.onNode(hasSetTextAction()).performTextInput("合成回复")
        compose.onNodeWithText("发送").performClick()
        compose.onNodeWithText("合成平台暂时不可用").assertExists()
        assertEquals("合成回复", drafts["other:account:42"]?.text)
        compose.onNodeWithText("发送").performClick()
        compose.waitUntil { sent }
        assertTrue(drafts.isEmpty())
    }
}
