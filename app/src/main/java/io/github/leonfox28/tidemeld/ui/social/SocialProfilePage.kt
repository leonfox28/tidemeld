package io.github.leonfox28.tidemeld.ui.social

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import io.github.leonfox28.tidemeld.core.paging.ListLoad
import io.github.leonfox28.tidemeld.ui.widget.*

/** One profile layout; adapters own requests, cursors and account-bound actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> SocialProfilePage(
    title: String,
    profile: ProfilePresentation,
    posts: ListLoad<T>?,
    failure: Exception?,
    emptyText: String,
    key: (T) -> Any,
    onRetry: () -> Unit,
    onRetryPosts: () -> Unit,
    onRefresh: suspend () -> Unit,
    onLoadMore: suspend () -> Unit,
    actions: ProfileActions? = null,
    badge: @Composable () -> Unit = {},
    details: @Composable () -> Unit = {},
    row: @Composable (T) -> Unit,
) {
    val heading: @Composable () -> Unit = {
        Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    if (posts == null) {
        Scaffold(topBar = { TopAppBar(title = heading, navigationIcon = { BackButton() }) }) {
            padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                if (failure != null) ErrorRetry(failure, onRetry) else CircularProgressIndicator()
            }
        }
    } else {
        Scaffold(snackbarHost = { AppSnackbarHost() }) { padding ->
            HidingAppBarBody(title = heading) {
                SocialContentList(
                    posts,
                    key,
                    emptyText,
                    onRetryPosts,
                    onRefresh,
                    onLoadMore,
                    padding = PaddingValues(bottom = padding.calculateBottomPadding()),
                    header = {
                        item(key = "header") {
                            SocialProfileHeader(profile, onRetry, badge, details, actions)
                        }
                        item(key = "line") { HorizontalDivider() }
                    },
                    row = row,
                )
            }
        }
    }
}
