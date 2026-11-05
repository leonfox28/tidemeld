package io.github.leonfox28.tidemeld.ui.x

import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import io.github.leonfox28.tidemeld.ui.navigation.*
import io.github.leonfox28.tidemeld.ui.post.*
import io.github.leonfox28.tidemeld.ui.widget.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

private val xTokens =
    Regex(
        """https?://[^\s<>]+|(?<![\p{L}\p{N}_@])@[A-Za-z0-9_]{1,15}(?![A-Za-z0-9_])|(?<![\p{L}\p{N}_])#[\p{L}\p{M}\p{N}_]+"""
    )

/** Converts X text into shared runs without interpreting it as Weibo HTML. */
fun xTextSegments(text: String): List<PostTextSegment> = buildList {
    var offset = 0
    for (match in xTokens.findAll(text)) {
        if (match.range.first > offset)
            add(PostTextSegment.Plain(text.substring(offset, match.range.first)))
        val raw = match.value
        var label = raw
        val destination =
            when {
                raw.startsWith("@") -> "https://x.com/${raw.drop(1)}"
                raw.startsWith("#") ->
                    "https://x.com/search"
                        .toHttpUrl()
                        .newBuilder()
                        .addQueryParameter("q", raw)
                        .build()
                        .toString()
                else -> {
                    label =
                        label.trimEnd('.', ',', '!', '?', ';', ':', '，', '。', '！', '？', '；', '：')
                    for ((close, open) in listOf(')' to '(', ']' to '[', '}' to '{')) {
                        while (
                            label.endsWith(close) &&
                                label.count { it == close } > label.count { it == open }
                        ) label = label.dropLast(1)
                    }
                    label
                }
            }
        val url = destination.toHttpUrlOrNull()
        if (url != null) add(PostTextSegment.Link(label, url.toString()))
        else add(PostTextSegment.Plain(label))
        if (label.length < raw.length) add(PostTextSegment.Plain(raw.drop(label.length)))
        offset = match.range.last + 1
    }
    if (offset < text.length) add(PostTextSegment.Plain(text.substring(offset)))
}

@Composable
fun XPostText(
    text: String,
    owner: String,
    modifier: Modifier = Modifier,
    author: String? = null,
    style: TextStyle = LocalTextStyle.current,
    selectable: Boolean = false,
    maxLines: Int = Int.MAX_VALUE,
) {
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    val segments =
        remember(text, author) {
            (author?.let { listOf(PostTextSegment.Plain("@$it：")) } ?: emptyList()) +
                xTextSegments(text)
        }
    PostText(
        segments,
        modifier,
        style,
        selectable,
        maxLines,
        onLink = { value ->
            val url = value.toHttpUrlOrNull()
            val parts = url?.pathSegments.orEmpty()
            if (
                url?.host in listOf("x.com", "www.x.com", "twitter.com", "www.twitter.com") &&
                    parts.size >= 3 &&
                    parts[1] == "status" &&
                    parts[2].isNotEmpty() &&
                    parts[2].all(Char::isDigit)
            )
                navigator.push(Route.XDetail(owner, parts[2], null))
            else context.openExternally(value, snackbars, scope)
        },
    )
}
