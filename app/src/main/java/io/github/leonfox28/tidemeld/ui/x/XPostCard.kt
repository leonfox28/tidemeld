package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.util.formatCount
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.theme.KeepTextSize
import io.github.leonfox28.tidemeld.ui.widget.*
import kotlinx.coroutines.launch

@Composable
fun XPostCard(post: XPost, owner: String, onReply: (() -> Unit)? = null) {
    val graph = LocalAppGraph.current
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val overlays = LocalOverlays.current
    val scope = rememberCoroutineScope()
    val snapshot by graph.xInteractions.states.collectAsStateWithLifecycle()
    val accounts by graph.accounts.accounts.collectAsStateWithLifecycle()
    val state = graph.xInteractions.state(owner, post, snapshot)
    val available = accounts.any { it.key == owner && !it.expired } && !state.busy
    var repostMenu by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    fun open() {
        navigator.push(Route.XDetail(owner, post.originalId, post))
    }
    fun web() {
        navigator.push(Route.AccountWeb(owner, post.url))
    }
    fun write(action: XWrite) {
        graph.appScope.launch {
            try {
                graph.xInteractions.write(owner, post, action)
            } catch (error: Exception) {
                snackbars.showError(error, navigator)
            }
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        post.repostedBy?.let { Text("$it 转发", style = MaterialTheme.typography.labelSmall) }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            post.avatar?.let { WeiboImage(it, Modifier.size(40.dp).clip(CircleShape)) }
            Column(Modifier.weight(1f).clickable(onClick = ::open)) {
                Text(post.author, style = MaterialTheme.typography.titleSmall)
                Text(
                    "@${post.handle}" + (post.createdAt?.let { " · ${formatPostTime(it)}" } ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (post.promoted) Text("广告", style = MaterialTheme.typography.labelSmall)
            Box {
                IconButton(onClick = { moreMenu = true }) { Icon(Icons.Default.MoreHoriz, "更多选项") }
                DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                    KeepTextSize {
                        DropdownMenuItem(
                            text = { Text("在 X 网页中打开") },
                            onClick = {
                                moreMenu = false
                                web()
                            },
                        )
                    }
                }
            }
        }
        Text(
            post.text,
            Modifier.fillMaxWidth().clickable(onClick = ::open),
            style = MaterialTheme.typography.bodyLarge,
        )
        if (post.pictures.isNotEmpty())
            PicGrid(
                post.pictures.map(MixedMedia::Pic),
                onClick = { navigator.push(Route.Viewer(post.pictures, it)) },
            )
        post.videoCover?.let { cover ->
            Box(
                Modifier.fillMaxWidth().height(200.dp).clickable(onClick = ::web),
                contentAlignment = Alignment.Center,
            ) {
                WeiboImage(cover, Modifier.fillMaxSize())
                FilledTonalIconButton(onClick = ::web) {
                    Icon(Icons.Default.PlayArrow, "在 X 中播放视频")
                }
            }
        }
        post.quote?.let { quote ->
            OutlinedCard(
                onClick = { navigator.push(Route.XDetail(owner, quote.originalId, quote)) }
            ) {
                Column(Modifier.padding(12.dp)) {
                    Text(quote.author, style = MaterialTheme.typography.labelMedium)
                    Text(quote.text)
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Box {
                TextButton(onClick = { repostMenu = true }, enabled = available) {
                    Icon(
                        Icons.Default.Repeat,
                        null,
                        Modifier.size(18.dp),
                        tint =
                            if (state.metrics.reposted) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "${if (state.metrics.reposted) "已转发" else "转发"} ${formatCount(state.metrics.reposts)}"
                    )
                }
                DropdownMenu(expanded = repostMenu, onDismissRequest = { repostMenu = false }) {
                    KeepTextSize {
                        DropdownMenuItem(
                            text = { Text(if (state.metrics.reposted) "取消转发" else "转发到我的时间线") },
                            onClick = {
                                repostMenu = false
                                write(XWrite.Repost)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("引用转发") },
                            onClick = {
                                repostMenu = false
                                scope.launch {
                                    overlays.show<Boolean> { XComposer(owner, post, true, it) }
                                }
                            },
                        )
                    }
                }
            }
            TextButton(onClick = onReply ?: ::open) {
                Icon(Icons.Default.ChatBubbleOutline, null, Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("评论 ${formatCount(state.metrics.replies)}")
            }
            TextButton(onClick = { write(XWrite.Like) }, enabled = available) {
                Icon(
                    if (state.metrics.liked) Icons.Default.Favorite
                    else Icons.Outlined.FavoriteBorder,
                    null,
                    Modifier.size(18.dp),
                    tint =
                        if (state.metrics.liked) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    "${if (state.metrics.liked) "已赞" else "赞"} ${formatCount(state.metrics.likes)}"
                )
            }
        }
        if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
    }
}
