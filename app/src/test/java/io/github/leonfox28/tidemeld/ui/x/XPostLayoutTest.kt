package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.leonfox28.tidemeld.data.model.PicInfo
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.support.*
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.post.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w1000dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class XPostLayoutTest {
    @get:Rule val compose = createComposeRule()
    private val post =
        XPost(
            "42",
            "合成作者",
            "fixture",
            null,
            "合成正文",
            null,
            pictures = listOf(PicInfo.fromUrl("https://example.com/synthetic.jpg")),
        )

    @Test
    fun `X inherits Weibo wide card layout and original picture navigation`() {
        val navigator = Navigator()
        compose.setContent {
            TestHost(navigator = navigator) {
                Column(Modifier.verticalScroll(rememberScrollState())) { XPostCard(post, "x:7") }
            }
        }
        val text =
            compose.onNodeWithText("合成正文", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val media =
            compose.onNodeWithTag("media", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertEquals(text.left + 424, media.left, 1f)
        assertTrue(media.top < text.bottom)
        compose.onNodeWithTag("media", useUnmergedTree = true).performClick()
        assertEquals(Route.Viewer(post.pictures, 0), navigator.backStack.last())
    }

    @Test
    fun `video opens the shared native player instead of an account web page`() {
        val navigator = Navigator()
        val video =
            post.copy(
                pictures = emptyList(),
                videoCover = "https://media.test/cover.jpg",
                videoUrl = "https://media.test/video.mp4",
            )
        compose.setContent { TestHost(navigator = navigator) { XPostCard(video, "x:7") } }
        compose.onNodeWithContentDescription("播放视频").performClick()
        val route = navigator.backStack.last() as Route.Video
        assertEquals(video.videoCover, route.request.cover)
        assertEquals("https://x.com/", route.request.headers["Referer"])
    }

    @Test
    fun `detail uses full text width without duplicate footer or navigating to itself`() {
        val navigator = Navigator()
        compose.setContent {
            TestHost(navigator = navigator) {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    XPostCard(post, "x:7", detail = true)
                }
            }
        }
        val text =
            compose.onNodeWithText("合成正文", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val media =
            compose.onNodeWithTag("media", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertEquals(text.left, media.left, 1f)
        assertTrue(media.top >= text.bottom)
        compose.onNodeWithContentDescription("赞").assertDoesNotExist()
        compose.onNodeWithText("合成正文").performClick()
        assertEquals(listOf(Route.Home), navigator.backStack.toList())
    }

    @Test
    fun `pending shared action consumes taps without sending again or opening card`() {
        var opened = 0
        var liked = 0
        compose.setContent {
            TestHost {
                PostCard(
                    onOpen = { opened++ },
                    header = {},
                    body = { androidx.compose.material3.Text("正文") },
                    footer = {
                        PostInteractionBar(
                            PostInteractionActions(likePending = true, onLike = { liked++ })
                        )
                    },
                )
            }
        }
        compose.onNodeWithContentDescription("赞").performTouchInput { click() }
        assertEquals(0, opened)
        assertEquals(0, liked)
    }
}
