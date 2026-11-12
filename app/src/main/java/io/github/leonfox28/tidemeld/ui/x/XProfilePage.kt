package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.paging.PagedController
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.social.*
import io.github.leonfox28.tidemeld.ui.widget.loadErrorMessage
import kotlinx.coroutines.*

class XProfileModel(
    val target: XProfileUser,
    private val owner: String,
    private val interactions: XInteractions,
) : ViewModel() {
    var profile by mutableStateOf<XUserProfile?>(null)
        private set

    var error by mutableStateOf<Exception?>(null)
        private set

    var posts by mutableStateOf<PagedController<XPost>?>(null)
        private set

    var relationshipFailed by mutableStateOf(false)
        private set

    private var loading: Job? = null
    private var generation = 0

    init {
        target.id?.let(::startPosts)
        reload()
    }

    fun reload() {
        val ticket = ++generation
        loading?.cancel()
        error = null
        loading = viewModelScope.launch {
            try {
                loadProfile(ticket)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (ticket == generation) error = e
            }
        }
    }

    private suspend fun loadProfile(ticket: Int) {
        val result = interactions.profile(owner, profile?.user ?: target)
        currentCoroutineContext().ensureActive()
        if (ticket != generation) return
        profile = result
        error = null
        result.user.id?.let { uid ->
            if (posts == null) startPosts(uid)
            try {
                interactions.refreshRelationship(owner, uid)
                relationshipFailed = false
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                if (ticket == generation) relationshipFailed = true
            }
        }
    }

    private fun startPosts(uid: String) {
        posts =
            object : PagedController<XPost>(viewModelScope) {
                    override fun idOf(item: XPost) = item.id

                    override suspend fun fetchPage(cursor: String?) =
                        interactions.userPosts(owner, uid, cursor)
                }
                .also { it.start() }
    }

    suspend fun refresh() = supervisorScope {
        val ticket = ++generation
        loading?.cancel()
        val details = async { loadProfile(ticket) }
        val content = async { posts?.refresh() }
        // Finish both independent reads, preserving whichever one succeeds.
        val results = listOf(details, content).map { runCatching { it.await() } }
        results.forEach { it.getOrThrow() }
    }
}

@Composable
fun XProfilePage(owner: String, user: XProfileUser) {
    val graph = LocalAppGraph.current
    val navigator = io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator.current
    val model = viewModel { XProfileModel(user, owner, graph.xInteractions) }
    val p = model.profile
    val current = p?.user ?: user
    val relationships by graph.xInteractions.relationships.states.collectAsStateWithLifecycle()
    val relationship = current.id?.let { relationships[graph.xInteractions.key(owner, it)] }
    val loading = p == null && model.error == null
    val posts = model.posts?.state?.collectAsStateWithLifecycle()?.value
    SocialProfilePage(
        title = current.name ?: current.handle?.let { "@$it" } ?: "用户主页",
        profile =
            ProfilePresentation(
                current.name ?: current.handle,
                current.avatar,
                p?.coverUrl,
                listOf("关注" to p?.following, "粉丝" to p?.followers, "帖子" to p?.posts).mapNotNull {
                    (label, value) ->
                    (value ?: if (loading) 0L else null)?.let { ProfileCount(label, it) }
                },
                if (relationship != null) relationship.value.label
                else
                    when {
                        p == null -> null
                        p.followed && p.followsYou -> "互相关注"
                        p.followed -> "已关注"
                        p.followsYou -> "关注了你"
                        else -> null
                    },
                null,
                p?.description,
                loading,
                model.error?.let { "资料加载失败：${loadErrorMessage(it)}" },
            ),
        posts = posts,
        failure = model.error,
        emptyText = if (p?.protected == true) "暂无可查看的帖子" else "还没有帖子",
        key = { it.id },
        onRetry = model::reload,
        onRetryPosts = { model.posts?.reload() },
        onRefresh = { model.refresh() },
        onLoadMore = { model.posts?.loadMore() },
        actions =
            graph.xInteractions.relationshipActions(owner, current, model.relationshipFailed).let {
                actions ->
                current.handle?.let {
                    actions.withReport(graph.xReportAction(navigator, owner, "https://x.com/$it"))
                } ?: actions
            },
        badge = {
            if (p?.verified == true) {
                Spacer(Modifier.width(4.dp))
                Icon(
                    Icons.Default.Verified,
                    "已认证",
                    Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        },
        details = {
            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                current.handle?.let { Text("@$it", style = MaterialTheme.typography.bodySmall) }
                p?.location?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                if (p?.protected == true) Text("帖子已受保护", style = MaterialTheme.typography.bodySmall)
            }
        },
    ) {
        XPostCard(it, owner, profileHandle = current.handle)
    }
}
