package io.github.leonfox28.tidemeld.ui.social

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.theme.KeepTextSize
import io.github.leonfox28.tidemeld.ui.widget.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

data class ProfileAction(
    val id: String,
    val title: String,
    val destructive: Boolean = false,
    val confirmation: String? = null,
    val perform: suspend () -> Unit,
)

data class ProfileActions(
    val primary: ProfileAction? = null,
    val more: List<ProfileAction> = emptyList(),
    val busy: Boolean = false,
)

@Composable
fun SocialProfileActions(actions: ProfileActions, menuLabel: String = "更多用户操作") {
    var menu by remember { mutableStateOf(false) }
    SocialActionHost(actions.busy) { disabled, select ->
        Row {
            if (actions.busy)
                Box(
                    Modifier.width(80.dp).height(40.dp),
                    contentAlignment = androidx.compose.ui.Alignment.Center,
                ) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                }
            else
                actions.primary?.let { action ->
                    OutlinedButton(
                        onClick = { select(action) },
                        enabled = !disabled,
                        contentPadding = PaddingValues(horizontal = 12.dp),
                    ) {
                        Text(action.title, maxLines = 1)
                    }
                }
            if (actions.more.isNotEmpty())
                Box {
                    IconButton(
                        onClick = { menu = true },
                        enabled = !disabled,
                        modifier = Modifier.size(40.dp),
                    ) {
                        Icon(Icons.Default.MoreHoriz, menuLabel)
                    }
                    DropdownMenu(menu, onDismissRequest = { menu = false }) {
                        SocialActionMenuItems(actions.more, disabled) {
                            menu = false
                            select(it)
                        }
                    }
                }
        }
    }
}

/** Long-press menus reuse confirmation and account-bound action execution. */
@Composable
fun SocialContextMenu(
    actions: ProfileActions,
    content: @Composable (openMenu: () -> Unit) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    SocialActionHost(actions.busy) { disabled, select ->
        Box {
            content { if (!disabled) menu = true }
            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                SocialActionMenuItems(actions.more, disabled) {
                    menu = false
                    select(it)
                }
            }
        }
    }
}

@Composable
private fun SocialActionMenuItems(
    actions: List<ProfileAction>,
    disabled: Boolean,
    select: (ProfileAction) -> Unit,
) {
    KeepTextSize {
        Column {
            actions.forEach { action ->
                DropdownMenuItem(
                    text = {
                        Text(
                            action.title,
                            color =
                                if (action.destructive) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.onSurface,
                        )
                    },
                    enabled = !disabled,
                    onClick = { select(action) },
                )
            }
        }
    }
}

@Composable
private fun SocialActionHost(
    busy: Boolean,
    content: @Composable (disabled: Boolean, select: (ProfileAction) -> Unit) -> Unit,
) {
    val graph = LocalAppGraph.current
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    var running by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf<ProfileAction?>(null) }
    fun run(action: ProfileAction) {
        confirming = null
        if (running) return
        running = true
        graph.appScope.launch {
            try {
                action.perform()
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                snackbars.showError(error, navigator)
            } finally {
                running = false
            }
        }
    }
    content(busy || running) { action ->
        if (!busy && !running) {
            if (action.confirmation != null) confirming = action else run(action)
        }
    }
    confirming?.let { action ->
        AppAlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text(action.title) },
            text = { Text(action.confirmation.orEmpty()) },
            confirmButton = { TextButton(onClick = { run(action) }) { Text(action.title) } },
            dismissButton = { TextButton(onClick = { confirming = null }) { Text("取消") } },
        )
    }
}

fun profileActions(
    name: String,
    state: ProfileRelationshipState,
    follow: suspend (Boolean) -> Unit,
    block: (suspend (Boolean) -> Unit)?,
    reposts: (suspend (Boolean) -> Unit)?,
    refresh: suspend () -> Unit,
): ProfileActions {
    val value = state.value
    if (state.needsRefresh)
        return ProfileActions(
            ProfileAction("refresh", "刷新状态", perform = refresh),
            busy = state.busy,
        )
    val removing = value.following || value.requested
    val primary =
        if (value.blocking == true) null
        else
            ProfileAction(
                "follow",
                if (value.requested) "取消申请" else if (removing) "取消关注" else "关注",
                confirmation =
                    if (removing) "确定${if (value.requested) "取消关注申请" else "取消关注"}“$name”？"
                    else null,
                perform = { follow(!removing) },
            )
    val more = buildList {
        if (block != null && value.blocking != null)
            add(
                ProfileAction(
                    "block",
                    if (value.blocking) "取消拉黑" else "拉黑",
                    destructive = !value.blocking,
                    confirmation =
                        if (value.blocking) "取消拉黑“$name”？不会自动重新关注。" else "确定拉黑“$name”？这也会解除关注关系。",
                    perform = { block(!value.blocking) },
                )
            )
        if (
            value.following &&
                value.blocking != true &&
                value.showsReposts != null &&
                reposts != null
        )
            add(
                ProfileAction(
                    "reposts",
                    if (value.showsReposts) "关闭转帖" else "开启转帖",
                    perform = { reposts(!value.showsReposts) },
                )
            )
    }
    return ProfileActions(primary, more, state.busy)
}
