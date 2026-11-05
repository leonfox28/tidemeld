package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.R
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.widget.*
import kotlinx.coroutines.launch

/** X supplies content and account-bound actions to the same card as Weibo. */
@Composable
fun XPostCard(post: XPost, owner: String, detail: Boolean = false) {
    val navigator = LocalNavigator.current
    val actions = rememberXPostActions(owner, post)
    val hasMedia = post.media.isNotEmpty()
    PostCard(
        detail = detail,
        activity = post.repostedBy?.let { "$it 转发" },
        onOpen = { navigator.push(Route.XDetail(owner, post.originalId, post)) },
        header = {
            PostHeader(
                name = post.author,
                metadata =
                    "@${post.handle}" + (post.createdAt?.let { " · ${formatPostTime(it)}" } ?: ""),
                sourceIcon = R.drawable.ic_platform_x,
                sourceLabel = "X",
                tags = if (post.promoted) listOf("广告") else emptyList(),
                avatar = {
                    Box(
                        Modifier.size(40.dp).clip(CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (post.avatar != null) WeiboImage(post.avatar, Modifier.fillMaxSize())
                        else Icon(Icons.Default.Person, null)
                    }
                },
            )
        },
        body = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    post.text,
                    style =
                        MaterialTheme.typography.bodyMedium.copy(
                            fontSize = 15.sp,
                            lineHeight = (15 * 1.45).sp,
                        ),
                )
                if (detail || post.quote != null) XMedia(post, owner)
            }
        },
        aside =
            when {
                post.quote != null -> ({
                        val quote = post.quote
                        QuotedPost(
                            onOpen = {
                                navigator.push(Route.XDetail(owner, quote.originalId, quote))
                            }
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    "@${quote.author}：${quote.text}",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                XMedia(quote, owner)
                            }
                        }
                    })
                !detail && hasMedia -> ({ XMedia(post, owner) })
                else -> null
            },
        footer = { PostInteractionBar(actions) },
    )
}

@Composable
internal fun XMedia(post: XPost, owner: String, compact: Boolean = false) {
    val navigator = LocalNavigator.current
    val graph = LocalAppGraph.current
    val items = post.media
    val pics = items.filterIsInstance<MixedMedia.Pic>().map { it.pic }
    fun open(index: Int) {
        val before = items.take(index)
        when (val item = items[index]) {
            is MixedMedia.Pic ->
                navigator.push(Route.Viewer(pics, before.count { it is MixedMedia.Pic }))
            is MixedMedia.Video ->
                navigator.push(
                    Route.Video(
                        xVideoRequest(
                            graph,
                            owner,
                            post.originalId,
                            before.count { it is MixedMedia.Video },
                            item.video,
                        )
                    )
                )
        }
    }
    val singleVideo = (items.singleOrNull() as? MixedMedia.Video)?.video
    if (compact && items.isNotEmpty()) PostCommentMedia(items, ::open)
    else if (singleVideo != null) VideoCover(singleVideo) { open(0) }
    else if (items.isNotEmpty()) PicGrid(items, onClick = ::open)
}

@Composable
fun rememberXPostActions(
    owner: String,
    post: XPost,
    onReply: (() -> Unit)? = null,
): PostInteractionActions {
    val graph = LocalAppGraph.current
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val overlays = LocalOverlays.current
    val scope = rememberCoroutineScope()
    val snapshot by graph.xInteractions.states.collectAsStateWithLifecycle()
    val accounts by graph.accounts.accounts.collectAsStateWithLifecycle()
    val state = graph.xInteractions.state(owner, post, snapshot)
    val available = accounts.any { it.key == owner && !it.expired }
    fun write(action: XWrite) {
        graph.appScope.launch {
            try {
                graph.xInteractions.write(owner, post, action)
            } catch (error: Exception) {
                snackbars.showError(error, navigator)
            }
        }
    }
    return PostInteractionActions(
        reposts = state.metrics.reposts,
        comments = state.metrics.replies,
        likes = state.metrics.likes,
        liked = state.metrics.liked,
        reposted = state.metrics.reposted,
        likePending = state.busy,
        repostPending = state.busy,
        onLike = if (available) ({ write(XWrite.Like) }) else null,
        onComment = onReply ?: { navigator.push(Route.XDetail(owner, post.originalId, post)) },
        onRepost =
            if (!available) null
            else
                ({
                    scope.launch {
                        val choice =
                            overlays.show<Int> { close ->
                                OverlaySheet(close) { dismiss ->
                                    ListItem(
                                        headlineContent = {
                                            Text(if (state.metrics.reposted) "取消转发" else "转发到我的时间线")
                                        },
                                        modifier = Modifier.clickable { dismiss(1) },
                                    )
                                    ListItem(
                                        headlineContent = { Text("引用转发") },
                                        modifier = Modifier.clickable { dismiss(2) },
                                    )
                                    ListItem(
                                        headlineContent = { Text("取消") },
                                        modifier = Modifier.clickable { dismiss(null) },
                                    )
                                }
                            }
                        when (choice) {
                            1 -> write(XWrite.Repost)
                            2 -> overlays.show<Boolean> { XComposer(owner, post, true, it) }
                        }
                    }
                    Unit
                }),
    )
}
