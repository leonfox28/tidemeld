package io.github.leonfox28.tidemeld.ui.timeline

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.accounts.*
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.core.paging.ListLoad
import io.github.leonfox28.tidemeld.core.paging.PagedState
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.WeiboUser
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.notifications.UNREAD_RECHECK_MS
import io.github.leonfox28.tidemeld.ui.shell.LocalTabReselect
import io.github.leonfox28.tidemeld.ui.status.rememberGuestStatusCardActions
import io.github.leonfox28.tidemeld.ui.status.rememberStatusCardActions
import io.github.leonfox28.tidemeld.ui.theme.KeepTextSize
import io.github.leonfox28.tidemeld.ui.widget.ErrorRetry
import io.github.leonfox28.tidemeld.ui.widget.KeepAtTop
import io.github.leonfox28.tidemeld.ui.widget.LoadMoreFooter
import io.github.leonfox28.tidemeld.ui.widget.LoadMoreTrigger
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.UserAvatar
import io.github.leonfox28.tidemeld.ui.widget.readingPadding
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCard
import kotlinx.coroutines.launch

/** The home tab: public posts for guests, the following feed after sign-in. */
@Composable
fun TimelinePage(padding: PaddingValues) {
    val graph = LocalAppGraph.current
    val session by graph.session.state.collectAsStateWithLifecycle()
    val uid = (session as? SessionState.SignedIn)?.account?.uid
    val navigator = LocalNavigator.current
    val settings by graph.settings.settings.collectAsStateWithLifecycle()
    val accounts by graph.accounts.accounts.collectAsStateWithLifecycle()
    val selection = settings.feedSelection
    var menu by remember { mutableStateOf(false) }
    var currentUser by remember(uid) { mutableStateOf<WeiboUser?>(null) }
    LaunchedEffect(uid) {
        if (uid != null) {
            try {
                val user = graph.api.fetchProfile(uid = uid).user
                if ((graph.session.state.value as? SessionState.SignedIn)?.account?.uid == uid)
                    currentUser = user
            } catch (_: WeiboException) {
                // The profile remains reachable while its avatar is unavailable.
            }
        }
    }
    val area =
        Modifier.fillMaxSize()
            .windowInsetsPadding(
                WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)
            )
    Column(area) {
        Box(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp)) {
            Box(Modifier.align(Alignment.Center)) {
                TextButton(
                    onClick = { menu = true },
                    modifier = Modifier.semantics { contentDescription = "选择信息流" },
                ) {
                    Text(selection.label, style = MaterialTheme.typography.titleMedium)
                    Icon(Icons.Default.ExpandMore, null)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    KeepTextSize {
                        Column {
                            FeedSelection.entries.forEach { choice ->
                                DropdownMenuItem(
                                    text = { Text(choice.label) },
                                    trailingIcon = {
                                        if (selection == choice) Icon(Icons.Default.Check, null)
                                    },
                                    onClick = {
                                        menu = false
                                        graph.settings.update { it.copy(feedSelection = choice) }
                                    },
                                )
                            }
                        }
                    }
                }
            }
            if (uid == null) {
                FilledTonalIconButton(
                    onClick = { navigator.push(Route.Accounts) },
                    modifier = Modifier.align(Alignment.CenterStart).size(48.dp),
                ) {
                    Icon(Icons.Outlined.Person, contentDescription = "账号管理")
                }
            } else {
                IconButton(
                    onClick = { navigator.push(Route.Accounts) },
                    modifier =
                        Modifier.align(Alignment.CenterStart).size(48.dp).semantics {
                            contentDescription = "账号管理"
                        },
                ) {
                    UserAvatar(currentUser, size = 36.dp)
                }
            }
        }
        if (accounts.isEmpty() && selection != FeedSelection.X)
            Timeline(null, padding, Modifier.weight(1f))
        else SocialTimeline(selection, padding, Modifier.weight(1f))
    }
}

@Composable
private fun Timeline(uid: String?, padding: PaddingValues, modifier: Modifier) {
    val graph = LocalAppGraph.current
    val timeline = if (uid == null) graph.guestTimeline else graph.timeline
    LaunchedEffect(uid) { timeline.start() }
    val state by timeline.state.collectAsStateWithLifecycle()
    when (val load = state) {
        ListLoad.Loading ->
            Box(modifier, contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        is ListLoad.Failed ->
            ErrorRetry(load.error, onRetry = timeline::reload, modifier = modifier)
        is ListLoad.Ready -> StatusList(load.list, padding, modifier, guest = uid == null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StatusList(
    timeline: PagedState<Status>,
    padding: PaddingValues,
    modifier: Modifier,
    guest: Boolean,
) {
    val graph = LocalAppGraph.current
    val controller = if (guest) graph.guestTimeline else graph.timeline
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val actions = if (guest) rememberGuestStatusCardActions() else rememberStatusCardActions()
    var refreshing by remember { mutableStateOf(false) }
    val unread = LocalAppGraph.current.unread
    fun refresh() {
        if (refreshing) return
        // The user asked for what's new; that includes notifications.
        if (!guest) unread.requestCheck(UNREAD_RECHECK_MS)
        refreshing = true
        scope.launch {
            try {
                controller.refresh()
            } catch (e: WeiboException) {
                snackbars.currentSnackbarData?.dismiss()
                launch { snackbars.showSnackbar(e.message) }
            } finally {
                refreshing = false
            }
        }
    }

    // Tapping the open tab again: back to the top, or a refresh from there.
    val reselects = LocalTabReselect.current
    LaunchedEffect(reselects) {
        reselects.collect {
            if (listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 0) {
                listState.animateScrollToItem(0)
            } else {
                refresh()
            }
        }
    }
    KeepAtTop(listState, timeline.items)
    // After a failure, loading more waits for the retry button.
    LoadMoreTrigger(
        listState,
        onNearEnd =
            if (timeline.loadMoreError == null) ({ scope.launch { controller.loadMore() } })
            else null,
    )
    PullToRefreshBox(isRefreshing = refreshing, onRefresh = ::refresh, modifier = modifier) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val contentPadding = readingPadding(maxWidth, padding, feed = true)
            LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = contentPadding) {
                if (timeline.items.isEmpty()) {
                    item {
                        Box(
                            Modifier.fillMaxWidth().padding(top = 160.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(if (guest) "暂时没有公开微博，下拉刷新试试" else "还没有微博，下拉刷新试试")
                        }
                    }
                } else {
                    items(timeline.items, key = { it.id }) { status ->
                        StatusCard(status, actions = actions)
                        HorizontalDivider()
                    }
                    item(key = "footer") {
                        if (!guest)
                            LoadMoreFooter(
                                loading = timeline.loadingMore,
                                hasMore = timeline.hasMore,
                                error = timeline.loadMoreError,
                                onLoadMore = { scope.launch { controller.loadMore() } },
                            )
                    }
                }
                if (guest) {
                    item {
                        Column(
                            Modifier.fillMaxWidth().padding(20.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(
                                "游客仅可浏览部分公开微博，登录后查看更多及参与互动。",
                                style = MaterialTheme.typography.bodySmall,
                            )
                            TextButton(onClick = { navigator.push(Route.Login) }) { Text("登录查看更多") }
                        }
                    }
                }
            }
        }
    }
}
