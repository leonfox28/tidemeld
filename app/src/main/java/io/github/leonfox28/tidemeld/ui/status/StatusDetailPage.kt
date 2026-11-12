package io.github.leonfox28.tidemeld.ui.status

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.core.paging.ListLoad
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.core.util.formatPostTime
import io.github.leonfox28.tidemeld.data.model.Comment
import io.github.leonfox28.tidemeld.data.model.CommentOrder
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.withReply
import io.github.leonfox28.tidemeld.ui.comments.CommentThread
import io.github.leonfox28.tidemeld.ui.comments.CommentTile
import io.github.leonfox28.tidemeld.ui.comments.CommentsController
import io.github.leonfox28.tidemeld.ui.interactions.LikeKind
import io.github.leonfox28.tidemeld.ui.interactions.LikeTarget
import io.github.leonfox28.tidemeld.ui.interactions.confirmDelete
import io.github.leonfox28.tidemeld.ui.interactions.like
import io.github.leonfox28.tidemeld.ui.interactions.rememberLike
import io.github.leonfox28.tidemeld.ui.interactions.rememberStatusWrites
import io.github.leonfox28.tidemeld.ui.interactions.showCommentComposer
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.widget.BackButton
import io.github.leonfox28.tidemeld.ui.widget.ErrorRetry
import io.github.leonfox28.tidemeld.ui.widget.LocalOverlays
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.UserAvatar
import io.github.leonfox28.tidemeld.ui.widget.loadErrorMessage
import io.github.leonfox28.tidemeld.ui.widget.pagedItems
import io.github.leonfox28.tidemeld.ui.widget.showError
import io.github.leonfox28.tidemeld.ui.widget.showMessage
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCard
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCardActions
import io.github.leonfox28.tidemeld.ui.widget.text.StatusText
import kotlinx.coroutines.launch

private const val TITLE = "微博正文"

/**
 * A status with its full text, and its comments and reposts in tabs.
 *
 * [initial] (the status as the previous page showed it) shows until the full one arrives.
 */
@Composable
fun StatusDetailPage(id: String, initial: Status?) {
    val graph = LocalAppGraph.current
    val model = viewModel { StatusDetailViewModel(id, graph.api, graph.openLists) }
    val load by model.load.collectAsStateWithLifecycle()
    val status = load.status ?: initial
    if (status == null) {
        Loading(load.error, onRetry = model::reload)
    } else {
        Detail(model, status, loadFailed = load.status == null && load.error != null, load.error)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Loading(error: WeiboException?, onRetry: () -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text(TITLE) }, navigationIcon = { BackButton() }) }) {
        padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            if (error != null) ErrorRetry(error, onRetry) else CircularProgressIndicator()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun Detail(
    model: StatusDetailViewModel,
    status: Status,
    loadFailed: Boolean,
    error: WeiboException?,
) {
    val graph = LocalAppGraph.current
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val overlays = LocalOverlays.current
    val writes = rememberStatusWrites()
    val scope = rememberCoroutineScope()
    val session by graph.session.state.collectAsStateWithLifecycle()
    val me = (session as? SessionState.SignedIn)?.account?.uid
    val base = rememberStatusCardActions()
    val cardActions =
        remember(base, status.id) {
            base.copy(
                // Its own "展开" stays inert: the full text is shown or on its way.
                onExpand = { if (it.id != status.id) base.onExpand?.invoke(it) },
                // The page has nothing left to show.
                onDelete = { deleted ->
                    writes.delete(deleted) {
                        if (
                            (navigator.backStack.lastOrNull() as? Route.StatusDetail)?.id ==
                                model.id
                        ) {
                            navigator.pop()
                        }
                    }
                },
            )
        }
    val authorId = status.user?.id

    fun editComments(edit: (CommentsController) -> Unit) {
        if (authorId != null) graph.openLists.editComments(status.id, authorId, edit)
    }

    fun comment() = scope.launch {
        val sent =
            overlays.showCommentComposer(status.id, "写评论…", model.drafts, "status") { text, pid ->
                val comment = graph.api.postComment(status.id, text, pid = pid)
                model.count(status, comments = 1)
                model.tab = DetailTab.Comments
                comment?.let { new -> editComments { it.prepend(new) } }
            }
        if (sent) snackbars.showMessage("评论成功", graph.appScope)
    }

    fun reply(target: Comment) = scope.launch {
        val name = target.user?.screenName
        val hint = if (name == null) "回复评论…" else "回复 @$name"
        val sent =
            overlays.showCommentComposer(status.id, hint, model.drafts, target.id) { text, pid ->
                val reply = graph.api.postComment(status.id, text, replyTo = target.id, pid = pid)
                // Weibo counts replies among a status's comments.
                model.count(status, comments = 1)
                editComments { list -> list.replace(target.id) { it.withReply(reply) } }
            }
        if (sent) snackbars.showMessage("回复成功", graph.appScope)
    }

    fun delete(comment: Comment) = scope.launch {
        if (!overlays.confirmDelete(offerChoice = false) || !model.deleting.add(comment.id))
            return@launch
        try {
            graph.api.deleteComment(comment.id)
            model.count(status, comments = -1)
            editComments { it.remove(comment.id) }
            snackbars.showMessage("已删除", graph.appScope)
        } catch (e: WeiboException) {
            launch { snackbars.showError(e, navigator) }
        } finally {
            model.deleting -= comment.id
        }
    }

    val comments = authorId?.let { model.comments(status, it, model.order) }
    val reposts = if (model.tab == DetailTab.Reposts) model.reposts(status) else null
    val list = if (model.tab == DetailTab.Reposts) reposts else comments
    // Each list's own state, keyed on the list, so switching lists (or
    // orders) never shows one's state as another's, not even for a frame.
    val commentsLoad =
        key(comments) { comments?.state?.collectAsStateWithLifecycle()?.value } ?: ListLoad.Loading
    val repostsLoad =
        key(reposts) { reposts?.state?.collectAsStateWithLifecycle()?.value } ?: ListLoad.Loading
    val listLoad: ListLoad<*> = if (model.tab == DetailTab.Reposts) repostsLoad else commentsLoad

    val postItems: LazyListScope.() -> Unit = {
        item(key = "status") {
            StatusCard(status, detail = true, actions = cardActions)
        }
        if (loadFailed) {
            item(key = "failed") {
                LoadFailedBar(loadErrorMessage(error), onRetry = model::reload)
            }
        }
    }
    val responseItems: LazyListScope.() -> Unit = {
        stickyHeader(key = "tabs") {
            Tabs(
                status,
                repostsCount = model.repostsCount(status),
                commentsCount = model.commentsCount(status),
                tab = model.tab,
                onTab = { model.tab = it },
            )
        }
        when {
            model.tab == DetailTab.Reposts && reposts != null ->
                pagedItems(
                    repostsLoad,
                    key = { it.id },
                    onRetry = reposts::reload,
                    onLoadMore = { scope.launch { reposts.loadMore() } },
                    emptyText = "还没有人转发",
                ) {
                    RepostTile(it, base)
                }
            comments != null -> {
                item(key = "order") {
                    OrderSwitch(model.order) { model.order = it }
                }
                pagedItems(
                    commentsLoad,
                    key = { it.id },
                    onRetry = comments::reload,
                    onLoadMore = { scope.launch { comments.loadMore() } },
                    emptyText = "还没有评论",
                ) { comment ->
                    CommentTile(
                        comment,
                        authorId = authorId,
                        actions = base,
                        onThread = {
                            navigator.push(
                                Route.Comments(CommentThread(comment, status.id, authorId))
                            )
                        },
                        onClick = if (comment.canReply) ({ reply(comment) }) else null,
                        onDelete =
                            if (me != null && comment.user?.id == me) {
                                { delete(comment) }
                            } else null,
                    )
                }
            }
            else ->
                item(key = "no-comments") {
                    Box(
                        Modifier.fillMaxWidth().padding(40.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("无法加载这条微博的评论")
                    }
                }
        }
    }

    val shown = rememberLike(LikeTarget(LikeKind.Status, status.id), status.like)
    PostDetailLayout(
        title = TITLE,
        actions =
            if (status.user == null) null
            else
                PostInteractionActions(
                    likes = shown.like.count,
                    liked = shown.like.liked,
                    likePending = shown.pending,
                    onComment = { comment() },
                    onRepost = { writes.repost(status) { model.count(status, reposts = 1) } },
                    onLike = shown.onToggle,
                ),
        onRefresh = { model.refresh(status) },
        onLoadMore =
            list?.let { controller ->
                val ready = listLoad as? ListLoad.Ready
                if (ready?.list?.loadMoreError == null)
                    ({
                        scope.launch { controller.loadMore() }
                        Unit
                    })
                else null
            },
        postItems = postItems,
        responseItems = responseItems,
    )
}

@Composable
private fun LoadFailedBar(message: String, onRetry: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Row(
        Modifier.fillMaxWidth()
            .background(colors.errorContainer)
            .padding(start = 16.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "正文加载失败：$message",
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            color = colors.onErrorContainer,
        )
        TextButton(onClick = onRetry) { Text("重试") }
    }
}

/**
 * The repost and comment tabs with their counts (with what the user added or deleted here), and the
 * like count (the like button is in the bottom bar).
 */
@Composable
private fun Tabs(
    status: Status,
    repostsCount: Int,
    commentsCount: Int,
    tab: DetailTab,
    onTab: (DetailTab) -> Unit,
) {
    val like = rememberLike(LikeTarget(LikeKind.Status, status.id), status.like).like
    PostResponseHeader(
        tabs =
            listOf(
                PostResponseTab("reposts", "转发", repostsCount),
                PostResponseTab("comments", "评论", commentsCount),
            ),
        selected = if (tab == DetailTab.Reposts) "reposts" else "comments",
        likes = like.count,
        onSelect = { onTab(if (it == "reposts") DetailTab.Reposts else DetailTab.Comments) },
    )
}

@Composable
private fun OrderSwitch(order: CommentOrder, onChange: (CommentOrder) -> Unit) {
    Row(Modifier.padding(start = 10.dp, top = 4.dp, end = 10.dp)) {
        for ((value, label) in listOf(CommentOrder.Hot to "按热度", CommentOrder.Time to "按时间")) {
            val selected = value == order
            Text(
                label,
                modifier =
                    Modifier.clip(RoundedCornerShape(4.dp))
                        .then(if (selected) Modifier else Modifier.clickable { onChange(value) })
                        .padding(6.dp),
                style = MaterialTheme.typography.bodySmall,
                color =
                    if (selected) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = if (selected) FontWeight.SemiBold else null,
            )
        }
    }
}

@Composable
private fun RepostTile(status: Status, actions: StatusCardActions) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val onOpen = actions.onOpen
    Row(
        Modifier.fillMaxWidth()
            .then(if (onOpen != null) Modifier.clickable { onOpen(status) } else Modifier)
            .padding(16.dp, 12.dp)
    ) {
        UserAvatar(status.user, size = 32.dp, onClick = actions.onUser)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                status.user?.screenName ?: "微博用户",
                maxLines = 1,
                style = MaterialTheme.typography.bodyMedium,
                color = muted,
                fontWeight = FontWeight.Medium,
            )
            Spacer(Modifier.height(4.dp))
            StatusText(
                status.text,
                urls = status.urls,
                style =
                    MaterialTheme.typography.bodyMedium.copy(
                        fontSize = 15.sp,
                        lineHeight = (15 * 1.45).sp,
                    ),
                onLink = actions.onLink,
            )
            status.createdAt?.let {
                Spacer(Modifier.height(6.dp))
                Text(formatPostTime(it), style = MaterialTheme.typography.bodySmall, color = muted)
            }
        }
    }
}
