package io.github.leonfox28.tidemeld.ui.widget.text

import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import io.github.leonfox28.tidemeld.data.model.UrlEntity
import io.github.leonfox28.tidemeld.ui.post.*

/**
 * The body of a status: text with tappable links, topics, mentions and inline emoticons.
 *
 * @param text the status `text` HTML.
 * @param hiddenPictures ids of pictures whose links to leave out, e.g. as they show below.
 * @param author shown as `@author：` before the text, for retweeted posts.
 * @param onExpand called when "展开" at the end of a truncated long post is tapped.
 */
@Composable
fun StatusText(
    text: String,
    modifier: Modifier = Modifier,
    urls: List<UrlEntity> = emptyList(),
    hiddenPictures: List<String> = emptyList(),
    author: String? = null,
    style: TextStyle = LocalTextStyle.current,
    onLink: ((StatusLink) -> Unit)? = null,
    onExpand: (() -> Unit)? = null,
) {
    val segments =
        remember(text, urls, hiddenPictures, author) {
            buildList {
                if (author != null) {
                    add(TextSegment.Link("@$author", StatusLink.Mention(author)))
                    add(TextSegment.Plain("："))
                }
                addAll(parseStatusText(text, urls, hiddenPictures))
            }
        }
    PostText(
        segments.mapIndexed { i, segment ->
            when (segment) {
                is TextSegment.Plain -> PostTextSegment.Plain(segment.text)
                is TextSegment.Link ->
                    PostTextSegment.Link(segment.text, i.toString(), segment.iconUrl)
                is TextSegment.Emoticon -> PostTextSegment.Emoticon(segment.url, segment.alt)
                TextSegment.Expand -> PostTextSegment.Expand
            }
        },
        modifier,
        style,
        onLink = { id ->
            (segments.getOrNull(id.toIntOrNull() ?: -1) as? TextSegment.Link)?.let {
                onLink?.invoke(it.link)
            }
        },
        onExpand = onExpand,
    )
}
