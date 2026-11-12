package io.github.leonfox28.tidemeld.ui.post

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.AppGraph
import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.net.SessionExpiredException
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.core.settings.SettingsController
import io.github.leonfox28.tidemeld.data.model.Comment
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.WeiboUser
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.profile.WeiboProfileControls
import io.github.leonfox28.tidemeld.ui.social.ProfileAction
import io.github.leonfox28.tidemeld.ui.social.ProfileActions
import io.github.leonfox28.tidemeld.ui.webview.AccountWebPage

object ContentBlock {
    fun key(owner: String, user: String) = "$owner/$user"

    fun hides(users: List<String>, owner: String?, blocked: Set<String>) =
        owner != null && users.any { key(owner, it) in blocked }
}

fun SettingsController.recordBlock(owner: String, user: String, blocked: Boolean) {
    val key = ContentBlock.key(owner, user)
    update { it.copy(blockedUsers = if (blocked) it.blockedUsers + key else it.blockedUsers - key) }
}

enum class WeiboReportKind(val value: String) {
    Post("1"),
    Comment("2"),
    User("3"),
}

fun weiboReportUrl(id: String, kind: WeiboReportKind): String =
    Uri.parse("https://service.account.weibo.com/reportspamobile")
        .buildUpon()
        .appendQueryParameter("rid", id)
        .appendQueryParameter("type", kind.value)
        .build()
        .toString()

data class PlatformReport(val owner: String, val url: String, val instructions: String)

@Composable
fun PlatformReportPage(report: PlatformReport) {
    AccountWebPage(report.owner, report.url) {
        Text(
            report.instructions,
            Modifier.fillMaxWidth().padding(12.dp),
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

val AppGraph.weiboContentOwner: String?
    get() = (session.state.value as? SessionState.SignedIn)?.account?.uid?.let { "weibo:$it" }

fun AppGraph.reportAction(
    navigator: Navigator,
    owner: String?,
    url: String,
    instructions: String,
): ProfileAction {
    val account = owner?.let(accounts::find)
    return ProfileAction(
        "report",
        "举报",
        perform = {
            if (owner == null || account == null || account.expired) {
                navigator.push(
                    Route.PlatformLogin(
                        if (owner?.startsWith("x:") == true) SocialPlatform.X
                        else SocialPlatform.Weibo
                    )
                )
            } else {
                if (accounts.find(owner)?.revision != account.revision)
                    throw SessionExpiredException()
                navigator.push(Route.Report(PlatformReport(owner, url, instructions)))
            }
        },
    )
}

fun AppGraph.weiboReportAction(navigator: Navigator, id: String, kind: WeiboReportKind) =
    reportAction(
        navigator,
        weiboContentOwner,
        weiboReportUrl(id, kind),
        "请在微博官方页面选择举报原因并提交。处理结果由微博通知；打开此页面不表示举报已提交。",
    )

fun AppGraph.weiboSafetyActions(
    navigator: Navigator,
    id: String,
    kind: WeiboReportKind,
    user: WeiboUser?,
): ProfileActions {
    val actions = mutableListOf(weiboReportAction(navigator, id, kind))
    val owner = weiboContentOwner
    val source = owner?.let(accounts::find)
    if (
        user != null && source != null && !source.expired && user.id != source.session.account.uid
    ) {
        val controls = WeiboProfileControls(this)
        actions +=
            ProfileAction(
                "block",
                "拉黑此用户",
                destructive = true,
                confirmation = "用当前来源账号拉黑“${user.screenName}”？平台确认后，叠澜会立即隐藏此账号下该用户的内容，并解除关注关系。",
                perform = { controls.blockUser(user.id) },
            )
    }
    return ProfileActions(more = actions)
}

fun AppGraph.xReportAction(navigator: Navigator, owner: String, url: String) =
    reportAction(
        navigator,
        owner,
        url,
        "请在下方 X 原帖或用户主页的“⋯”菜单中选择“举报 / Report”，完成原因选择和提交。处理结果由 X 通知。",
    )

fun AppGraph.xSafetyActions(navigator: Navigator, owner: String, post: XPost): ProfileActions {
    val actions = mutableListOf(xReportAction(navigator, owner, post.url))
    val source = accounts.find(owner)
    if (
        post.authorId != null &&
            source != null &&
            !source.expired &&
            post.authorId != source.session.account.uid
    ) {
        actions +=
            ProfileAction(
                "block",
                "拉黑此用户",
                destructive = true,
                confirmation = "用当前来源账号拉黑“${post.author}”？平台确认后，叠澜会立即隐藏此账号下该用户的内容，并解除关注关系。",
                perform = { xInteractions.blockUser(owner, post.profileUser, source.revision) },
            )
    }
    return ProfileActions(more = actions)
}

fun ProfileActions?.withReport(report: ProfileAction): ProfileActions =
    (this ?: ProfileActions()).let { it.copy(more = it.more + report) }

val Status.contentAuthorIds: List<String>
    get() = listOfNotNull(user?.id) + retweeted?.contentAuthorIds.orEmpty()
val Comment.contentAuthorIds: List<String>
    get() = listOfNotNull(user?.id) + replies.flatMap { it.contentAuthorIds }
val XPost.contentAuthorIds: List<String>
    get() = listOfNotNull(authorId, repostedById) + quote?.contentAuthorIds.orEmpty()
