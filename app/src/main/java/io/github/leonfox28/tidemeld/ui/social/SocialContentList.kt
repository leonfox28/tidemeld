package io.github.leonfox28.tidemeld.ui.social

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.paging.ListLoad
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.widget.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> SocialContentList(
    load: ListLoad<T>,
    key: (T) -> Any,
    emptyText: String,
    onRetry: () -> Unit,
    onRefresh: suspend () -> Unit,
    onLoadMore: suspend () -> Unit,
    padding: PaddingValues = PaddingValues(0.dp),
    keepAtTop: Boolean = false,
    header: LazyListScope.() -> Unit = {},
    row: @Composable (T) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val state = rememberLazyListState()
    var refreshing by remember { mutableStateOf(false) }
    if (keepAtTop) KeepAtTop(state, (load as? ListLoad.Ready)?.list?.items)
    LoadMoreTrigger(
        state,
        if ((load as? ListLoad.Ready)?.list?.loadMoreError == null)
            ({
                scope.launch { onLoadMore() }
                Unit
            })
        else null,
    )
    PullToRefreshBox(
        refreshing,
        onRefresh = {
            refreshing = true
            scope.launch {
                try {
                    onRefresh()
                } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    launch { snackbars.showError(error, navigator) }
                } finally {
                    refreshing = false
                }
            }
        },
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            LazyColumn(
                Modifier.fillMaxSize(),
                state = state,
                contentPadding = readingPadding(maxWidth, padding),
            ) {
                header()
                pagedItems(
                    load,
                    key,
                    onRetry,
                    { scope.launch { onLoadMore() } },
                    emptyText,
                    dividerIndent = 0.dp,
                    itemContent = row,
                )
            }
        }
    }
}
