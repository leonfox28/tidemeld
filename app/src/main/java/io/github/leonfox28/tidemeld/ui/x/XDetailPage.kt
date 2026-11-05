package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.paging.PagedController
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.widget.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

class XDetailController(
    private val interactions: XInteractions,
    private val owner: String,
    private val id: String,
    initial: XPost?,
    scope: CoroutineScope,
) : PagedController<XPost>(scope) {
    val post = MutableStateFlow(initial)

    override fun idOf(item: XPost) = item.originalId

    override suspend fun fetchPage(cursor: String?) =
        interactions.conversation(owner, id, cursor).let { page ->
            page.post?.let { post.value = it }
            page.replies
        }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun XDetailPage(owner: String, id: String, initial: XPost?) {
    val graph = LocalAppGraph.current
    val scope = rememberCoroutineScope()
    val controller =
        remember(owner, id) { XDetailController(graph.xInteractions, owner, id, initial, scope) }
    val post by controller.post.collectAsStateWithLifecycle()
    val state by controller.state.collectAsStateWithLifecycle()
    val overlays = LocalOverlays.current
    fun reply() {
        post?.let { target ->
            scope.launch {
                if (overlays.show<Boolean> { XComposer(owner, target, false, it) } == true)
                    controller.reload()
            }
        }
    }
    LaunchedEffect(controller) { controller.start() }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("帖子") },
                navigationIcon = { BackButton() },
                actions = { IconButton(onClick = controller::reload) { Text("刷新") } },
            )
        },
        bottomBar = {
            if (post != null)
                Surface(tonalElevation = 3.dp) {
                    TextButton(
                        onClick = ::reply,
                        modifier = Modifier.fillMaxWidth().navigationBarsPadding(),
                    ) {
                        Text("写评论…")
                    }
                }
        },
    ) { padding ->
        BoxWithConstraints(Modifier.fillMaxSize()) {
            LazyColumn(
                contentPadding = readingPadding(maxWidth, padding),
                modifier = Modifier.fillMaxSize(),
            ) {
                post?.let { value ->
                    item(key = "focal") {
                        XPostCard(value, owner, onReply = ::reply)
                        HorizontalDivider()
                    }
                }
                item {
                    Text(
                        "评论",
                        Modifier.padding(16.dp),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
                pagedItems(
                    state,
                    key = { "reply:${it.id}" },
                    onRetry = controller::reload,
                    onLoadMore = { scope.launch { controller.loadMore() } },
                    emptyText = "还没有评论",
                ) {
                    XPostCard(it, owner)
                }
            }
        }
    }
}
