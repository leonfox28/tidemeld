package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.runtime.*
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.post.PostComposer

@Composable
fun XComposer(owner: String, post: XPost, quote: Boolean, close: (Boolean?) -> Unit) {
    val graph = LocalAppGraph.current
    val key = remember {
        graph.xInteractions.key(owner, post.originalId) + if (quote) ":quote" else ":reply"
    }
    PostComposer(
        hint = if (quote) "引用转发…" else "回复 @${post.handle}",
        drafts = graph.xInteractions.drafts,
        draftKey = key,
        close = close,
        context = "使用 X · ${graph.accounts.find(owner)?.name.orEmpty()}",
        send = { text, _ ->
            graph.xInteractions.write(owner, post, if (quote) XWrite.Quote else XWrite.Reply, text)
            Unit
        },
    )
}
