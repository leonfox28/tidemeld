package io.github.leonfox28.tidemeld.ui.auth

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.accounts.*
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.widget.AppAlertDialog
import io.github.leonfox28.tidemeld.ui.widget.CloseButton
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlatformPickerPage() {
    val navigator = LocalNavigator.current
    Scaffold(
        topBar = { TopAppBar(title = { Text("选择登录平台") }, navigationIcon = { CloseButton() }) }
    ) { padding ->
        Column(Modifier.padding(padding)) {
            for (platform in SocialPlatform.entries) {
                ListItem(
                    headlineContent = { Text(platform.label) },
                    supportingContent = { Text("使用官方网页登录，可添加多个账号") },
                    leadingContent = { Icon(Icons.Outlined.Person, null) },
                    modifier = Modifier.clickable { navigator.push(Route.PlatformLogin(platform)) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountsPage() {
    val graph = LocalAppGraph.current
    val navigator = LocalNavigator.current
    val accounts by graph.accounts.accounts.collectAsStateWithLifecycle()
    val session by graph.session.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var removing by remember { mutableStateOf<SocialAccount?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("账号管理") },
                navigationIcon = { CloseButton() },
                actions = {
                    IconButton(onClick = { navigator.push(Route.Login) }) {
                        Icon(Icons.Default.Add, "添加账号")
                    }
                },
            )
        }
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            item {
                Text(
                    "已登录账号的信息流会一起显示。移除账号仅清除本机登录状态。",
                    Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            error?.let { message ->
                item {
                    Text(message, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error)
                }
            }
            for (platform in SocialPlatform.entries) {
                item {
                    Text(
                        platform.label,
                        Modifier.padding(16.dp),
                        style = MaterialTheme.typography.titleSmall,
                    )
                }
                items(accounts.filter { it.platform == platform }, key = { it.key }) { account ->
                    ListItem(
                        headlineContent = { Text(account.name) },
                        supportingContent = {
                            val active =
                                platform == SocialPlatform.Weibo &&
                                    (session as? SessionState.SignedIn)?.account?.uid ==
                                        account.session.account.uid
                            Text(
                                if (account.expired) "登录已过期"
                                else if (active) "已登录 · 微博功能当前账号" else "已登录"
                            )
                        },
                        trailingContent = {
                            Row {
                                if (account.expired)
                                    TextButton(
                                        onClick = { navigator.push(Route.PlatformLogin(platform)) }
                                    ) {
                                        Text("重新登录")
                                    }
                                else if (platform == SocialPlatform.Weibo)
                                    TextButton(onClick = { graph.accounts.useWeibo(account.key) }) {
                                        Text("使用")
                                    }
                                if (!account.expired)
                                    TextButton(
                                        onClick = {
                                            navigator.push(
                                                when (platform) {
                                                    SocialPlatform.Weibo ->
                                                        Route.ForAccount(
                                                            account.key,
                                                            Route.Profile(
                                                                account.session.account.uid
                                                            ),
                                                        )
                                                    SocialPlatform.X ->
                                                        Route.XProfile(
                                                            account.key,
                                                            io.github.leonfox28.tidemeld.data.x
                                                                .XProfileUser(
                                                                    id =
                                                                        account.session.account.uid,
                                                                    name = account.name,
                                                                ),
                                                        )
                                                }
                                            )
                                        }
                                    ) {
                                        Text("主页")
                                    }
                                TextButton(onClick = { removing = account }) { Text("移除") }
                            }
                        },
                    )
                }
                item {
                    TextButton(
                        onClick = { navigator.push(Route.PlatformLogin(platform)) },
                        modifier = Modifier.padding(horizontal = 8.dp),
                    ) {
                        Text("添加${platform.label}账号")
                    }
                }
            }
        }
    }
    removing?.let { account ->
        AppAlertDialog(
            onDismissRequest = { removing = null },
            title = { Text("移除账号") },
            text = { Text("移除 ${account.platform.label} · ${account.name}？其他账号保持登录。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        removing = null
                        scope.launch {
                            try {
                                graph.accounts.remove(account.key)
                            } catch (_: Exception) {
                                error = "移除失败，请重试"
                            }
                        }
                    }
                ) {
                    Text("移除")
                }
            },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("取消") } },
        )
    }
}
