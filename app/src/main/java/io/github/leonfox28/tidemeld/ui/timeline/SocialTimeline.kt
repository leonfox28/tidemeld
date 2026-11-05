package io.github.leonfox28.tidemeld.ui.timeline

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.accounts.FeedSelection
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.shell.LocalTabReselect
import io.github.leonfox28.tidemeld.ui.status.rememberStatusCardActions
import io.github.leonfox28.tidemeld.ui.widget.*
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SocialTimeline(selection: FeedSelection, padding: PaddingValues, modifier: Modifier) {
    val graph = LocalAppGraph.current
    val controller = graph.socialFeed
    val accounts by graph.accounts.accounts.collectAsStateWithLifecycle()
    val state by controller.state.collectAsStateWithLifecycle()
    val navigator = LocalNavigator.current
    fun refresh() {
        graph.unread.requestCheck(io.github.leonfox28.tidemeld.ui.notifications.UNREAD_RECHECK_MS)
        controller.refresh()
    }
    val list = rememberLazyListState()
    KeepAtTop(list, state.items)
    val identities = accounts.map { Triple(it.key, it.revision, it.expired) }
    LaunchedEffect(selection, identities) { controller.select(selection) }
    LaunchedEffect(selection) { list.scrollToItem(0) }
    val reselects = LocalTabReselect.current
    LaunchedEffect(reselects) {
        reselects.collect {
            if (list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 0)
                list.animateScrollToItem(0)
            else refresh()
        }
    }
    LoadMoreTrigger(
        list,
        onNearEnd = if (!state.loading && state.hasMore) controller::loadMore else null,
    )
    PullToRefreshBox(
        isRefreshing = state.loading,
        onRefresh = ::refresh,
        modifier = modifier,
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            LazyColumn(
                Modifier.fillMaxSize(),
                state = list,
                contentPadding = readingPadding(maxWidth, padding, feed = true),
            ) {
                if (state.errors.isNotEmpty())
                    item {
                        Column(Modifier.padding(16.dp)) {
                            state.errors.values.forEach {
                                Text(
                                    it,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error,
                                )
                            }
                            Row {
                                TextButton(onClick = controller::retry) { Text("重试失败账号") }
                                TextButton(onClick = { navigator.push(Route.Accounts) }) {
                                    Text("账号管理")
                                }
                            }
                        }
                    }
                if (state.items.isEmpty() && !state.loading)
                    item {
                        Column(
                            Modifier.fillMaxWidth().padding(top = 100.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(
                                if (
                                    accounts.none {
                                        selection.platform == null ||
                                            it.platform == selection.platform
                                    }
                                )
                                    "登录后查看${selection.label}信息流"
                                else "暂时没有动态，下拉刷新试试"
                            )
                            TextButton(onClick = { navigator.push(Route.Login) }) { Text("添加账号") }
                        }
                    }
                items(state.items, key = { it.key }) { item ->
                    val account = accounts.firstOrNull { it.key == item.owner }
                    Text(
                        "${account?.platform?.label.orEmpty()} · ${account?.name.orEmpty()}",
                        Modifier.padding(start = 16.dp, top = 12.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    when (item) {
                        is FeedPost.Weibo -> {
                            val scoped = graph.forAccount(item.owner)
                            if (scoped != null)
                                CompositionLocalProvider(
                                    LocalAppGraph provides scoped,
                                    LocalNavigator provides
                                        remember(navigator, item.owner) {
                                            navigator.forAccount(item.owner)
                                        },
                                ) {
                                    StatusCard(item.post, actions = rememberStatusCardActions())
                                }
                        }
                        is FeedPost.X -> XPostCard(item.post, item.owner)
                    }
                    HorizontalDivider()
                }
                if (state.hasMore)
                    item {
                        TextButton(
                            onClick = controller::loadMore,
                            enabled = !state.loading,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(if (state.loading) "加载中…" else "加载更多")
                        }
                    }
            }
        }
    }
}

@Composable
private fun XPostCard(post: XPost, owner: String) {
    val navigator = LocalNavigator.current
    fun open() {
        navigator.push(Route.AccountWeb(owner, post.url))
    }
    Column(
        Modifier.fillMaxWidth().clickable(onClick = ::open).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        post.repostedBy?.let { Text("$it 转发", style = MaterialTheme.typography.labelSmall) }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            post.avatar?.let { WeiboImage(it, Modifier.size(40.dp).clip(CircleShape)) }
            Column(Modifier.weight(1f)) {
                Text(post.author, style = MaterialTheme.typography.titleSmall)
                Text(
                    "@${post.handle}" + (post.createdAt?.let { " · ${formatPostTime(it)}" } ?: ""),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (post.promoted) Text("广告", style = MaterialTheme.typography.labelSmall)
        }
        Text(post.text, style = MaterialTheme.typography.bodyLarge)
        if (post.pictures.isNotEmpty())
            PicGrid(
                post.pictures.map(MixedMedia::Pic),
                onClick = { navigator.push(Route.Viewer(post.pictures, it)) },
            )
        post.videoCover?.let { cover ->
            Box(
                Modifier.fillMaxWidth().height(200.dp).clickable(onClick = ::open),
                contentAlignment = Alignment.Center,
            ) {
                WeiboImage(cover, Modifier.fillMaxSize())
                FilledTonalIconButton(onClick = ::open) {
                    Icon(Icons.Default.PlayArrow, "在 X 中播放视频")
                }
            }
        }
        post.quote?.let { quote ->
            OutlinedCard(onClick = { navigator.push(Route.AccountWeb(owner, quote.url)) }) {
                Column(Modifier.padding(12.dp)) {
                    Text(quote.author, style = MaterialTheme.typography.labelMedium)
                    Text(quote.text)
                }
            }
        }
        TextButton(onClick = ::open) { Text("在 X 中查看与互动") }
    }
}
