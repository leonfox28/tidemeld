package io.github.leonfox28.tidemeld.ui.profile

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Female
import androidx.compose.material.icons.filled.Male
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.data.model.WeiboUser
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.social.*
import io.github.leonfox28.tidemeld.ui.status.rememberStatusCardActions
import io.github.leonfox28.tidemeld.ui.widget.AppSnackbarHost
import io.github.leonfox28.tidemeld.ui.widget.BackButton
import io.github.leonfox28.tidemeld.ui.widget.ErrorRetry
import io.github.leonfox28.tidemeld.ui.widget.HidingAppBarBody
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
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
    val model = viewModel { ProfileViewModel(uid, screenName, graph.api, graph.openLists) }
    val load by model.profile.collectAsStateWithLifecycle()
    val user = load.profile?.user ?: initial
    val statuses = model.statuses
    val title: @Composable () -> Unit = {
        Text(
            user?.screenName ?: screenName.orEmpty(),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
    if (statuses == null) {
        Scaffold(topBar = { TopAppBar(title = title, navigationIcon = { BackButton() }) }) { padding
            ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                val error = load.error
                if (error != null) ErrorRetry(error, model::reload) else CircularProgressIndicator()
            }
        }
        return
    }
    Scaffold(snackbarHost = { AppSnackbarHost() }) { padding ->
        HidingAppBarBody(title = title) {
            ProfileView(model, statuses, load, initial, padding.calculateBottomPadding())
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileView(
    model: ProfileViewModel,
    statuses: UserStatusesController,
    load: ProfileLoad,
    initial: WeiboUser?,
    bottom: Dp,
) {
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val statusesLoad = key(statuses) { statuses.state.collectAsStateWithLifecycle().value }
    val base = rememberStatusCardActions()
    // This user's own avatar would only open this page again.
    val actions =
        remember(base, statuses.uid) {
            base.copy(onUser = { if (it.id != statuses.uid) base.onUser?.invoke(it) })
        }
    SocialContentList(
        statusesLoad,
        { it.id },
        "还没有微博",
        statuses::reload,
        { model.refresh() },
        { statuses.loadMore() },
        padding = PaddingValues(bottom = bottom),
        header = {
            item(key = "header") { Header(load, initial, onRetry = model::reload) }
            item(key = "line") { HorizontalDivider() }
        },
    ) {
        StatusCard(it, actions = actions)
    }
}

@Composable
private fun Header(load: ProfileLoad, initial: WeiboUser?, onRetry: () -> Unit) {
    val p = load.profile
    val failed = p == null && load.error != null
    val user = p?.user ?: initial
    val verified = user?.verifiedType
    val relation =
        when {
            p == null -> null
            p.following && p.followsMe -> "互相关注"
            p.following -> "已关注"
            p.followsMe -> "关注了你"
            else -> null
        }
    val loading = p == null && !failed
    val counts =
        listOf("关注" to p?.friendsCount, "粉丝" to p?.followersCount, "微博" to p?.statusesCount)
            .mapNotNull { (label, value) ->
                (value ?: if (loading) 0 else null)?.let { ProfileCount(label, it) }
            }
    SocialProfileHeader(
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
        onRetry,
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
    )
}
