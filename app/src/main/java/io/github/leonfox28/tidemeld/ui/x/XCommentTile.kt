package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.social.SocialProfileActions
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
    if (
        hideFilteredPost(
            (listOf(post.contentFilterText) + preview.map { it.contentFilterText }).joinToString(
                "\n"
            ),
            owner = owner,
            authors = post.contentAuthorIds + preview.flatMap { it.contentAuthorIds },
        )
    )
        return
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
            onAuthor = { navigator.push(Route.XProfile(owner, post.profileUser)) },
            onReply = ::reply,
            onLongClick = { menu = true },
            menu = {
                SocialProfileActions(
                    LocalAppGraph.current.xSafetyActions(navigator, owner, post),
                    menuLabel = "更多评论操作",
                )
            },
            avatar = {
                PostAvatar(
                    post.avatar,
                    post.author,
                    size = 32.dp,
                    onClick = { navigator.push(Route.XProfile(owner, post.profileUser)) },
                )
            },
            content = {
                if (post.text.isNotEmpty())
                    XPostText(
                        post.text,
                        owner,
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
                            xReplyReference(quote, owner, navigator)?.let { PostReplyContext(it) }
                            XPostText(
                                quote.text,
                                owner,
                                author = quote.author,
                                authorHandle = quote.handle,
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
                                XPostText(
                                    child.text.ifEmpty { "[媒体]" },
                                    owner,
                                    Modifier.padding(bottom = 4.dp),
                                    author = child.author,
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
