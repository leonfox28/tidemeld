package io.github.leonfox28.tidemeld.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Feedback
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.BuildConfig
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.widget.AppSnackbarHost
import io.github.leonfox28.tidemeld.ui.widget.BackButton
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.openExternally
import io.github.leonfox28.tidemeld.ui.widget.readingPadding

const val REPO_URL = "https://github.com/leonfox28/tidemeld"
const val ISSUES_URL = "$REPO_URL/issues"

// Kept in line with the README.
private val disclaimer =
    listOf(
        "叠澜是非官方客户端，与微博、X 及其运营方没有任何关联，仅供学习交流。",
        "不收费、不接受赞助，不提供批量下载、会员内容等功能。",
        "使用非官方客户端可能导致账号被风控或受到限制，风险由使用者自行承担。请遵守所使用平台的服务协议。",
        "如权利人认为本项目不妥，请到项目主页提 issue 联系，我们会及时处理。",
    )

private val privacy =
    listOf(
        "登录在所选平台的官方网页登录页中完成，叠澜的原生代码不读取你的密码或验证码。",
        "登录状态只保存在本机（Android Keystore），移除对应账号时清除。",
        "维护者不运营接收用户数据的后端，没有统计、埋点或崩溃上报。所需的登录凭据、搜索词和你提交的内容会直接发送给对应平台。",
        "只在你操作时请求对应平台，不在后台轮询或预取，请求频率有上限。遇到验证码时，由你本人在平台页面里完成。",
    )

/** What tidemeld is, the disclaimer, the privacy statement and licences. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutPage() {
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    Scaffold(
        topBar = { TopAppBar(title = { Text("关于") }, navigationIcon = { BackButton() }) },
        snackbarHost = { AppSnackbarHost() },
    ) { padding ->
        BoxWithConstraints(Modifier.fillMaxSize()) {
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding =
                    readingPadding(
                        maxWidth,
                        PaddingValues(
                            top = padding.calculateTopPadding() + 16.dp,
                            bottom = padding.calculateBottomPadding() + 16.dp,
                        ),
                    ),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                item { AppTitle() }
                item {
                    Spacer(Modifier.height(8.dp))
                    Text("开源、非商业的社交阅读客户端")
                }
                item {
                    Link(Icons.Outlined.Description, "使用条款", "内容与行为规则") {
                        navigator.push(Route.Terms)
                    }
                }
                item { Section("声明", disclaimer) }
                item { Section("隐私", privacy) }
                item { HorizontalDivider(Modifier.padding(vertical = 16.dp)) }
                item {
                    Link(Icons.Outlined.Description, "隐私政策", "数据使用、本地存储与删除方式") {
                        context.openExternally(
                            "$REPO_URL/blob/main/docs/PRIVACY.md",
                            snackbars,
                            scope,
                        )
                    }
                }
                item {
                    Link(Icons.Outlined.Feedback, "使用帮助与支持", "常见问题与联系维护者") {
                        context.openExternally(
                            "$REPO_URL/blob/main/docs/SUPPORT.md",
                            snackbars,
                            scope,
                        )
                    }
                }
                item {
                    Link(Icons.Outlined.Code, "项目主页", REPO_URL) {
                        context.openExternally(REPO_URL, snackbars, scope)
                    }
                }
                item {
                    Link(Icons.Outlined.Feedback, "问题反馈", "在 GitHub 上提 issue") {
                        context.openExternally(ISSUES_URL, snackbars, scope)
                    }
                }
                item {
                    Link(Icons.Outlined.Description, "开源许可", "叠澜以 GPL-3.0 发布；以及所用的第三方库") {
                        navigator.push(Route.Licenses)
                    }
                }
            }
        }
    }
}

/** The app's name and version. */
@Composable
internal fun AppTitle() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            "叠澜 Tidemeld",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "版本 ${BuildConfig.VERSION_NAME}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun Section(title: String, items: List<String>) {
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, top = 24.dp, end = 16.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(8.dp))
        for (item in items) {
            Row(Modifier.padding(bottom = 6.dp)) {
                Text("·  ")
                Text(item, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun Link(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        modifier = Modifier.clickable(onClick = onClick),
        supportingContent = { Text(subtitle) },
        leadingContent = { Icon(icon, contentDescription = null) },
    )
}
