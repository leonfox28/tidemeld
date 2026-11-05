package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.theme.KeepTextSize
import io.github.leonfox28.tidemeld.ui.widget.LocalOverlays
import kotlinx.coroutines.launch

/** X adapts its native replies and actions to the shared compact comment UI. */
@Composable
fun XCommentTile(
    post: XPost,
    owner: String,
    authorHandle: String? = null,
    preview: List<XPost> = emptyList(),
    onSent: () -> Unit = {},
) {
    val navigator = LocalNavigator.current
    val scope = rememberCoroutineScope()
    val overlays = LocalOverlays.current
    val clipboard = LocalClipboardManager.current
    var menu by remember { mutableStateOf(false) }
    fun reply() {
        scope.launch {
            if (overlays.show<Boolean> { XComposer(owner, post, false, it) } == true) onSent()
        }
    }
    fun thread() {
        navigator.push(Route.XDetail(owner, post.originalId, post))
    }
    val actions = rememberXPostActions(owner, post, ::reply)
    Box {
        PostComment(
            author = post.author,
            metadata =
                listOfNotNull(post.createdAt?.let { formatPostTime(it) }, "@${post.handle}")
                    .joinToString("  "),
            isAuthor = authorHandle != null && post.handle.equals(authorHandle, ignoreCase = true),
            onReply = ::reply,
            onLongClick = { menu = true },
            avatar = {
                Box(Modifier.fillMaxSize().clip(CircleShape), contentAlignment = Alignment.Center) {
                    if (post.avatar != null) WeiboImage(post.avatar, Modifier.fillMaxSize())
                    else Icon(Icons.Default.Person, null)
                }
            },
            content = {
                if (post.text.isNotEmpty())
                    Text(
                        post.text,
                        Modifier.padding(top = 4.dp),
                        style =
                            MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 15.sp,
                                lineHeight = (15 * 1.45).sp,
                            ),
                    )
                XMedia(post, owner, compact = true)
                post.quote?.let { quote ->
                    QuotedPost(
                        onOpen = { navigator.push(Route.XDetail(owner, quote.originalId, quote)) }
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(
                                "@${quote.author}：${quote.text}",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            XMedia(quote, owner, compact = true)
                        }
                    }
                }
            },
            like = {
                PostCommentLike(actions.likes, actions.liked, actions.onLike, actions.likePending)
            },
            replies =
                if (actions.comments > 0 || preview.isNotEmpty())
                    ({
                        PostCommentThread(maxOf(actions.comments, preview.size), ::thread) {
                            preview.take(2).forEach { child ->
                                Text(
                                    "@${child.author}：${child.text.ifEmpty { "[媒体]" }}",
                                    Modifier.padding(bottom = 4.dp),
                                    style = MaterialTheme.typography.bodyMedium,
                                    maxLines = 2,
                                )
                            }
                        }
                    })
                else null,
        )
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            KeepTextSize {
                Column {
                    DropdownMenuItem(
                        text = { Text("回复") },
                        onClick = {
                            menu = false
                            reply()
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("查看对话") },
                        onClick = {
                            menu = false
                            thread()
                        },
                    )
                    actions.onRepost?.let { repost ->
                        DropdownMenuItem(
                            text = { Text("转发") },
                            onClick = {
                                menu = false
                                repost()
                            },
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("复制") },
                        onClick = {
                            menu = false
                            clipboard.setText(AnnotatedString(post.text))
                        },
                    )
                }
            }
        }
    }
}
