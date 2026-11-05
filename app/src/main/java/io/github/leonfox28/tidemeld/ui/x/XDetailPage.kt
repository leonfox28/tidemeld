package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.paging.ListLoad
import io.github.leonfox28.tidemeld.core.paging.PagedController
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.post.*
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
    val actions = post?.let { rememberXPostActions(owner, it, ::reply) }
    PostDetailLayout(
        title = "帖子",
        actions = actions,
        onRefresh = { controller.refresh() },
        onLoadMore =
            if ((state as? ListLoad.Ready)?.list?.loadMoreError == null)
                ({
                    scope.launch { controller.loadMore() }
                    Unit
                })
            else null,
        postItems = {
            post?.let { value -> item(key = "focal") { XPostCard(value, owner, detail = true) } }
        },
        responseItems = {
            item {
                PostResponseHeader(
                    listOf(PostResponseTab("comments", "评论", actions?.comments ?: 0)),
                    "comments",
                    actions?.likes ?: 0,
                    onSelect = {},
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
        },
    )
}
