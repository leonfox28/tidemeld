package io.github.leonfox28.tidemeld.ui.timeline

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.accounts.FeedSelection
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.shell.LocalTabReselect
import io.github.leonfox28.tidemeld.ui.status.rememberStatusCardActions
import io.github.leonfox28.tidemeld.ui.widget.*
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCard
import io.github.leonfox28.tidemeld.ui.x.XPostCard

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
    // Defer to the next measure: a platform switch can replace the items
    // while the initial layout is still completing.
    LaunchedEffect(selection) { list.requestScrollToItem(0) }
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
