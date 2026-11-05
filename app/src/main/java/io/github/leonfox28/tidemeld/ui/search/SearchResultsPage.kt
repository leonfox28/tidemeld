package io.github.leonfox28.tidemeld.ui.search

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.paging.ListLoad
import io.github.leonfox28.tidemeld.core.paging.PagedController
import io.github.leonfox28.tidemeld.core.util.formatCount
import io.github.leonfox28.tidemeld.data.api.WeiboApi
import io.github.leonfox28.tidemeld.data.model.Paged
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.Topic
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.social.SocialContentList
import io.github.leonfox28.tidemeld.ui.status.rememberStatusCardActions
import io.github.leonfox28.tidemeld.ui.webview.weiboSearchUrl
import io.github.leonfox28.tidemeld.ui.widget.AppSnackbarHost
import io.github.leonfox28.tidemeld.ui.widget.HidingAppBarBody
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCard
import io.github.leonfox28.tidemeld.ui.widget.text.StatusLink
import kotlinx.coroutines.CoroutineScope

/** The posts found for [query], newest first, with the topic searched for, if one was. */
class SearchResultsController(private val api: WeiboApi, val query: String, scope: CoroutineScope) :
    PagedController<Status>(scope) {
    /** The topic searched for, as the first page describes it; null when the query is no topic. */
    var topic by mutableStateOf<Topic?>(null)
        private set

    override suspend fun fetchPage(cursor: String?): Paged<Status> {
        val results = api.searchStatuses(query, page = cursor?.toInt() ?: 1)
        if (cursor == null) topic = results.topic
        return results.statuses
    }

    override fun idOf(item: Status) = item.id
}

class SearchResultsViewModel(query: String, api: WeiboApi) : ViewModel() {
    val results = SearchResultsController(api, query, viewModelScope).also { it.start() }
}

/**
 * The posts across Weibo that match a query, newest first, as cards like the timeline's. A topic's
 * lead and counts head its posts.
 *
 * Weibo's own results page, ranked and split into tabs (users, videos, …), is a tap away in the
 * in-app browser.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchResultsPage(query: String) {
    val api = LocalAppGraph.current.api
    val results = viewModel { SearchResultsViewModel(query, api) }.results
    // A value, not a state the list reads itself, for KeepAtTop.
    val load = results.state.collectAsStateWithLifecycle().value
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val base = rememberStatusCardActions()
    val actions =
        remember(base, query) {
            base.copy(
                // The topic searched for would only open this page again.
                onLink = { link ->
                    if (link is StatusLink.Topic && "#${link.topic}#" == query) return@copy
                    base.onLink?.invoke(link)
                }
            )
        }
    val topic = if (load is ListLoad.Ready) results.topic else null
    Scaffold(snackbarHost = { AppSnackbarHost() }) { padding ->
        HidingAppBarBody(
            title = { Text(query, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            actions = {
                IconButton(onClick = { navigator.push(Route.Web(weiboSearchUrl(query))) }) {
                    Icon(Icons.Filled.Language, contentDescription = "网页版搜索结果")
                }
            },
        ) {
            SocialContentList(
                load,
                { it.id },
                "没有找到相关微博",
                results::reload,
                { results.refresh() },
                { results.loadMore() },
                padding = PaddingValues(bottom = padding.calculateBottomPadding()),
                keepAtTop = true,
                header = {
                    if (topic != null) {
                        item(key = "topic") { TopicHeader(topic) }
                        item(key = "line") { HorizontalDivider() }
                    }
                },
            ) {
                StatusCard(it, actions = actions)
            }
        }
    }
}

@Composable
private fun TopicHeader(topic: Topic) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val counts =
        listOf(topic.reads to "阅读", topic.mentions to "讨论", topic.authors to "原创人数")
            .filter { (count, _) -> count != null && count > 0 }
            .map { (count, label) -> "${formatCount(count!!)}$label" }
    Column(Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            topic.imageUrl?.let {
                WeiboImage(it, Modifier.size(56.dp).clip(RoundedCornerShape(8.dp)))
                Spacer(Modifier.width(14.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(
                    "#${topic.name}#",
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                if (counts.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        counts.joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = muted,
                    )
                }
            }
        }
        topic.summary?.let { summary ->
            Spacer(Modifier.height(12.dp))
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = muted)) { append("导语：") }
                    append(summary)
                },
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}
