package io.github.leonfox28.tidemeld.ui.profile

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Female
import androidx.compose.material.icons.filled.Male
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.data.model.WeiboUser
import io.github.leonfox28.tidemeld.ui.social.*
import io.github.leonfox28.tidemeld.ui.status.rememberStatusCardActions
import io.github.leonfox28.tidemeld.ui.widget.VerifiedIcon
import io.github.leonfox28.tidemeld.ui.widget.loadErrorMessage
import io.github.leonfox28.tidemeld.ui.widget.showsVerified
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCard

/**
 * A user's profile and statuses: the user with [uid], or else the one named [screenName].
 *
 * [initial] (the user as the previous page showed them) shows until the profile arrives.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfilePage(uid: String? = null, screenName: String? = null, initial: WeiboUser? = null) {
    val graph = LocalAppGraph.current
    val model = viewModel { ProfileViewModel(uid, screenName, graph.api, graph.openLists, graph) }
    val load by model.profile.collectAsStateWithLifecycle()
    val user = load.profile?.user ?: initial
    val statuses = model.statuses
    val base = rememberStatusCardActions()
    val own = load.profile?.user?.id ?: uid
    val actions =
        remember(base, own) {
            base.copy(onUser = { if (it.id != own) base.onUser?.invoke(it) })
        }
    val posts = statuses?.state?.collectAsStateWithLifecycle()?.value
    val relationships by graph.profileRelationships.states.collectAsStateWithLifecycle()
    val p = load.profile
    val failed = p == null && load.error != null
    val verified = user?.verifiedType
    val relation = remember(p, relationships) { p?.let { model.controls?.state(it)?.value?.label } }
    val loading = p == null && !failed
    val counts =
        listOf("关注" to p?.friendsCount, "粉丝" to p?.followersCount, "微博" to p?.statusesCount)
            .mapNotNull { (label, value) ->
                (value ?: if (loading) 0 else null)?.let { ProfileCount(label, it) }
            }
    SocialProfilePage(
        title = user?.screenName ?: screenName.orEmpty(),
        posts = posts,
        failure = load.error,
        emptyText = "还没有微博",
        key = { it.id },
        onRetry = model::reload,
        onRetryPosts = { statuses?.reload() },
        onRefresh = { model.refresh() },
        onLoadMore = { statuses?.loadMore() },
        profile =
            ProfilePresentation(
                user?.screenName,
                user?.avatarUrl,
                p?.coverUrl,
                counts,
                relation,
                p?.verifiedReason?.let { "微博认证：$it" },
                p?.description,
                loading,
                if (failed) "资料加载失败：${loadErrorMessage(load.error)}" else null,
            ),
        actions = p?.let { model.controls?.actions(it) },
        badge = {
            if (showsVerified(verified)) {
                Spacer(Modifier.width(4.dp))
                VerifiedIcon(verified!!, size = 18.dp)
            }
        },
        details = {
            val muted = MaterialTheme.colorScheme.onSurfaceVariant
            val typography = MaterialTheme.typography
            if (p != null && (p.gender != null || p.location != null)) {
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    when (p.gender) {
                        "m" ->
                            Icon(
                                Icons.Filled.Male,
                                null,
                                Modifier.size(16.dp),
                                tint = Color(0xFF42A5F5),
                            )
                        "f" ->
                            Icon(
                                Icons.Filled.Female,
                                null,
                                Modifier.size(16.dp),
                                tint = Color(0xFFF06292),
                            )
                    }
                    p.location?.let {
                        Spacer(Modifier.width(4.dp))
                        Text(it, style = typography.bodySmall, color = muted)
                    }
                }
            }
        },
        row = { StatusCard(it, actions = actions) },
    )
}
