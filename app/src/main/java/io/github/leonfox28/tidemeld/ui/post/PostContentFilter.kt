package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.settings.ContentFilter
import io.github.leonfox28.tidemeld.data.model.Comment
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.x.XPost
import io.github.leonfox28.tidemeld.ui.widget.text.plainStatusText

/** Return before mounting media, actions or accessibility content for a matching post. */
@Composable
fun hideFilteredPost(text: String): Boolean {
    val settings by LocalAppGraph.current.settings.settings.collectAsStateWithLifecycle()
    val hidden = ContentFilter.matches(text, settings.filterKeywords)
    if (hidden)
        Text(
            "已按本地关键词过滤",
            Modifier.fillMaxWidth().padding(16.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodySmall,
        )
    return hidden
}

val Status.contentFilterText: String
    get() =
        listOf(
                user?.screenName.orEmpty(),
                plainStatusText(text),
                retweeted?.contentFilterText.orEmpty(),
            )
            .joinToString("\n")
val Comment.contentFilterText: String
    get() =
        (listOf(user?.screenName.orEmpty(), plainStatusText(text)) +
                replies.map { it.contentFilterText })
            .joinToString("\n")
val XPost.contentFilterText: String
    get() = listOf(author, handle, text, quote?.contentFilterText.orEmpty()).joinToString("\n")
