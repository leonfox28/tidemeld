package io.github.leonfox28.tidemeld.ui.widget

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.errors.*
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route

/** The message to show for a failed load. */
fun loadErrorMessage(error: Throwable?): String = AppFailure.of(error).message

/**
 * Calls [onNearEnd] as the user scrolls [state] close to its end, to load the next page before they
 * reach it. Only scrolling triggers it, so a list too short to scroll waits for its footer's
 * button.
 */
@Composable
fun LoadMoreTrigger(state: LazyListState, onNearEnd: (() -> Unit)?) {
    val nearEnd by rememberUpdatedState(onNearEnd)
    val extent = with(LocalDensity.current) { 800.dp.toPx() }
    LaunchedEffect(state) {
        snapshotFlow { state.firstVisibleItemIndex to state.firstVisibleItemScrollOffset }
            .collect {
                val info = state.layoutInfo
                val last = info.visibleItemsInfo.lastOrNull() ?: return@collect
                val pastViewport = last.offset + last.size - info.viewportEndOffset
                val itemsAfter = info.totalItemsCount - 1 - last.index
                val average = info.visibleItemsInfo.sumOf { it.size } / info.visibleItemsInfo.size
                if (pastViewport + itemsAfter * average < extent) nearEnd?.invoke()
            }
    }
}

/**
 * Keeps [state] at the very top when [items] change while it's there, as when a refresh brings
 * newer items. Left to itself, a lazy list keeps showing the item it showed first, which would
 * leave the new ones out of sight above it.
 *
 * The list's content has to get [items] by recomposition, as a value rather than a state it reads
 * itself: otherwise the list can measure them before this sees them.
 */
@Composable
fun KeepAtTop(state: LazyListState, items: List<*>?) {
    val shown = remember(state) { ShownItems(items) }
    // Applied before the list is measured with the new items, its position
    // still the one it had with the old.
    SideEffect {
        if (shown.items === items) return@SideEffect
        shown.items = items
        if (state.firstVisibleItemIndex == 0 && state.firstVisibleItemScrollOffset == 0) {
            state.requestScrollToItem(0)
        }
    }
}

private class ShownItems(var items: List<*>?)

/**
 * The end of a paged list: a spinner while the next page loads, the error and a retry button when
 * it failed, or a note that nothing is left.
 */
@Composable
fun LoadMoreFooter(
    loading: Boolean,
    hasMore: Boolean,
    error: Throwable?,
    onLoadMore: () -> Unit,
    endText: String = "没有更多了",
) {
    val navigator = LocalNavigator.current
    Box(Modifier.fillMaxWidth().padding(vertical = 20.dp), contentAlignment = Alignment.Center) {
        when {
            loading -> CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
            error != null ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(AppFailure.of(error).message, style = MaterialTheme.typography.bodySmall)
                    if (AppFailure.of(error).recovery != null) {
                        val recovery = AppFailure.of(error).recovery!!
                        TextButton(onClick = { navigator.recover(recovery, onLoadMore) }) {
                            Text(recovery.label)
                        }
                    } else {
                        TextButton(onClick = onLoadMore) { Text("重试") }
                    }
                }
            // Normally replaced by the spinner before it scrolls into view;
            // kept for lists too short to scroll.
            hasMore -> TextButton(onClick = onLoadMore) { Text("加载更多") }
            else ->
                Text(
                    endText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
        }
    }
}

/**
 * A failure in place of content, with a retry button; when Weibo wants a security check first, a
 * button to take it.
 */
@Composable
fun ErrorRetry(error: Throwable?, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    val navigator = LocalNavigator.current
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(loadErrorMessage(error), textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
            if (AppFailure.of(error).recovery != null) {
                val recovery = AppFailure.of(error).recovery!!
                Button(onClick = { navigator.recover(recovery, onRetry) }) { Text(recovery.label) }
            } else {
                FilledTonalButton(onClick = onRetry) { Text("重试") }
            }
        }
    }
}

/**
 * Tells the user why something they did failed; when Weibo wants a security check first, offers to
 * take it (they then try again themselves).
 */
suspend fun SnackbarHostState.showError(error: Throwable, navigator: Navigator) {
    val failure = AppFailure.of(error)
    if (failure.isCancelled) return
    currentSnackbarData?.dismiss()
    val result =
        showSnackbar(
            message = failure.message,
            actionLabel = failure.recovery?.label,
            duration = SnackbarDuration.Short,
        )
    if (result == SnackbarResult.ActionPerformed) failure.recovery?.let { navigator.recover(it) }
}

fun Navigator.recover(recovery: FailureRecovery, onVerified: (() -> Unit)? = null) {
    when (recovery) {
        FailureRecovery.SignIn -> push(Route.Accounts)
        is FailureRecovery.Verify -> push(Route.Web(recovery.url, onClose = onVerified))
    }
}
