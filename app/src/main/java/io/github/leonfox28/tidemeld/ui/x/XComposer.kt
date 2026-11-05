package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.widget.*
import kotlinx.coroutines.launch

@Composable
fun XComposer(owner: String, post: XPost, quote: Boolean, close: (Boolean?) -> Unit) {
    val graph = LocalAppGraph.current
    val scope = rememberCoroutineScope()
    val key = remember {
        graph.xInteractions.key(owner, post.originalId) + if (quote) ":quote" else ":reply"
    }
    var text by remember { mutableStateOf(graph.xInteractions.drafts[key].orEmpty()) }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    OverlaySheet(close, canDismiss = !sending) { dismiss ->
        Column(
            Modifier.fillMaxWidth().imePadding().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(if (quote) "引用转发" else "写评论", style = MaterialTheme.typography.titleLarge)
            Text(
                "使用 X · ${graph.accounts.find(owner)?.name.orEmpty()}",
                style = MaterialTheme.typography.labelMedium,
            )
            Text(
                "${if (quote) "引用" else "回复"} @${post.handle}",
                style = MaterialTheme.typography.bodySmall,
            )
            OutlinedTextField(
                value = text,
                onValueChange = {
                    text = it
                    graph.xInteractions.drafts[key] = it
                },
                modifier = Modifier.fillMaxWidth().heightIn(min = 150.dp, max = 280.dp),
                enabled = !sending,
                placeholder = { Text("写下你的想法…") },
            )
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = { dismiss(null) }, enabled = !sending) { Text("取消") }
                Button(
                    enabled = !sending && text.isNotBlank(),
                    onClick = {
                        sending = true
                        error = null
                        scope.launch {
                            try {
                                graph.xInteractions.write(
                                    owner,
                                    post,
                                    if (quote) XWrite.Quote else XWrite.Reply,
                                    text,
                                )
                                graph.xInteractions.drafts.remove(key)
                                sending = false
                                dismiss(true)
                            } catch (failure: Exception) {
                                sending = false
                                error = loadErrorMessage(failure)
                            }
                        }
                    },
                ) {
                    Text(if (sending) "发送中…" else "发送")
                }
            }
        }
    }
}
