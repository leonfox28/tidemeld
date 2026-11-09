package io.github.leonfox28.tidemeld.ui.widget.text

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.leonfox28.tidemeld.support.TestHost
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.status.rememberStatusCardActions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
class StatusTextTapTest {
    @get:Rule val compose = createComposeRule()

    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun `tapping an inline video opens the shared player`() {
        val navigator = Navigator()
        compose.setContent {
            TestHost(navigator = navigator) {
                val actions = rememberStatusCardActions()
                StatusText(
                    "<a href=\"https://h5.video.weibo.com/show/1034:5000000000000001\">示例用户的微博视频</a>",
                    onLink = actions.onLink,
                )
            }
        }
        compose.onNodeWithText("示例用户的微博视频").performClick()
        assertTrue(navigator.backStack.last() is Route.Video)
    }

    @Test
    fun `a tap just below a link is not the link's`() {
        val links = mutableListOf<StatusLink>()
        var threads = 0
        compose.setContent {
            // As a thread preview: a reply that starts with a mention, then
            // the line that opens the thread.
            Column(Modifier.clickable { threads++ }) {
                StatusText("图片评论", author = "某人", onLink = { links += it })
                Text("共1条回复 >")
            }
        }

        compose.onNodeWithText("共1条回复 >").performClick()
        assertEquals(1, threads)
        assertEquals(emptyList<StatusLink>(), links)
    }
}
