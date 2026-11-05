package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.widget.AppSnackbarHost
import io.github.leonfox28.tidemeld.ui.widget.BarsOnScroll
import io.github.leonfox28.tidemeld.ui.widget.HidingAppBar
import io.github.leonfox28.tidemeld.ui.widget.LoadMoreTrigger
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.ReadingPanes
import io.github.leonfox28.tidemeld.ui.widget.WindowSize
import io.github.leonfox28.tidemeld.ui.widget.readingPadding
import io.github.leonfox28.tidemeld.ui.widget.showError
import io.github.leonfox28.tidemeld.ui.widget.windowSize
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Shared detail chrome, refresh, independent wide panes, scrolling bars and pagination. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PostDetailLayout(
    title: String,
    actions: PostInteractionActions?,
    onRefresh: suspend () -> Unit,
    onLoadMore: (() -> Unit)? = null,
    postItems: LazyListScope.() -> Unit,
    responseItems: LazyListScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    val snackbars = LocalSnackbars.current
    val navigator = LocalNavigator.current
    val threshold = with(LocalDensity.current) { BarsOnScroll.Threshold.toPx() }
    val bars = remember(threshold) { BarsOnScroll(threshold) }
    val hidden by
        animateFloatAsState(if (bars.visible) 0f else 1f, BarsOnScroll.spec(), label = "bars")
    var refreshing by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val split = windowSize() == WindowSize.Expanded
    LoadMoreTrigger(listState, onLoadMore)
    Scaffold(
        Modifier.nestedScroll(bars.connection),
        bottomBar = {
            if (actions != null) {
                val slide = Modifier.graphicsLayer { translationY = hidden * 1.5f * size.height }
                val bar: @Composable (Modifier) -> Unit = { modifier ->
                    PostDetailActions(actions, modifier)
                }
                // Under the lists it writes to.
                if (split) {
                    ReadingPanes(
                        slide,
                        divider = false,
                        fillHeight = false,
                        end = { bar(Modifier) },
                    )
                } else {
                    bar(slide)
                }
            }
        },
        snackbarHost = { AppSnackbarHost() },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        Column(
            Modifier.fillMaxSize()
                .windowInsetsPadding(
                    WindowInsets.safeDrawing.only(
                        WindowInsetsSides.Top + WindowInsetsSides.Horizontal
                    )
                )
        ) {
            HidingAppBar(bars.visible, title = { Text(title) })
            PullToRefreshBox(
                isRefreshing = refreshing,
                onRefresh = {
                    refreshing = true
                    scope.launch {
                        try {
                            onRefresh()
                        } catch (e: Exception) {
                            if (e is CancellationException) throw e
                            launch { snackbars.showError(e, navigator) }
                        } finally {
                            refreshing = false
                        }
                    }
                },
            ) {
                // Room to scroll the last item out from under the comment bar.
                val bottom = PaddingValues(bottom = padding.calculateBottomPadding())
                if (split) {
                    // The lists scroll on their own, leaving the status where it is.
                    ReadingPanes(
                        start = {
                            LazyColumn(Modifier.fillMaxSize(), contentPadding = bottom) {
                                postItems()
                            }
                        },
                        end = {
                            LazyColumn(
                                Modifier.fillMaxSize(),
                                state = listState,
                                contentPadding = bottom,
                            ) {
                                responseItems()
                            }
                        },
                    )
                } else {
                    BoxWithConstraints(Modifier.fillMaxSize()) {
                        LazyColumn(
                            Modifier.fillMaxSize(),
                            state = listState,
                            contentPadding = readingPadding(maxWidth, bottom),
                        ) {
                            postItems()
                            responseItems()
                        }
                    }
                }
            }
        }
    }
}
