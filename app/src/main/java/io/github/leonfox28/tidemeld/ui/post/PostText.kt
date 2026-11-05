package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import io.github.leonfox28.tidemeld.core.media.WeiboImage

/** Presentation runs with opaque action IDs; platforms resolve their own destinations. */
sealed interface PostTextSegment {
    data class Plain(val text: String) : PostTextSegment

    data class Link(val text: String, val link: String, val iconUrl: String? = null) :
        PostTextSegment

    data class Emoticon(val url: String, val alt: String) : PostTextSegment

    data object Expand : PostTextSegment
}

@Composable
fun PostText(
    segments: List<PostTextSegment>,
    modifier: Modifier = Modifier,
    style: TextStyle = LocalTextStyle.current,
    selectable: Boolean = false,
    maxLines: Int = Int.MAX_VALUE,
    onLink: ((String) -> Unit)? = null,
    onExpand: (() -> Unit)? = null,
) {
    val link by rememberUpdatedState(onLink)
    val expand by rememberUpdatedState(onExpand)
    val linkStyles = TextLinkStyles(SpanStyle(color = MaterialTheme.colorScheme.primary))
    val annotated = buildAnnotatedString {
        segments.forEachIndexed { i, segment ->
            when (segment) {
                is PostTextSegment.Plain -> append(segment.text)
                is PostTextSegment.Emoticon -> appendInlineContent("$i", segment.alt)
                is PostTextSegment.Link ->
                    withLink(
                        LinkAnnotation.Clickable("$i", linkStyles) { link?.invoke(segment.link) }
                    ) {
                        if (segment.iconUrl != null) appendInlineContent("$i", " ")
                        append(segment.text)
                    }
                PostTextSegment.Expand ->
                    withLink(LinkAnnotation.Clickable("expand", linkStyles) { expand?.invoke() }) {
                        append("展开")
                    }
            }
        }
    }
    val fontSize = if (style.fontSize.isSpecified) style.fontSize else 14.sp
    val iconSize = (fontSize.value * 1.2f).sp
    val inline =
        segments
            .withIndex()
            .mapNotNull { (i, segment) ->
                when (segment) {
                    is PostTextSegment.Emoticon ->
                        "$i" to inlineImage(segment.url, iconSize, segment.alt)
                    is PostTextSegment.Link ->
                        segment.iconUrl?.let {
                            "$i" to inlineImage(it, iconSize, null) { link?.invoke(segment.link) }
                        }
                    else -> null
                }
            }
            .toMap()
    // Links take taps on their glyphs only, as in Flutter: stretched to the
    // usual 48dp, a mention would take taps on the line below it, or on
    // "共N条回复" under a reply.
    val viewConfiguration = LocalViewConfiguration.current
    val exactTargets =
        remember(viewConfiguration) {
            object : ViewConfiguration by viewConfiguration {
                override val minimumTouchTargetSize = DpSize.Zero
            }
        }
    CompositionLocalProvider(LocalViewConfiguration provides exactTargets) {
        if (selectable)
            SelectionContainer {
                Text(
                    annotated,
                    modifier,
                    style = style,
                    inlineContent = inline,
                    maxLines = maxLines,
                )
            }
        else Text(annotated, modifier, style = style, inlineContent = inline, maxLines = maxLines)
    }
}

private fun inlineImage(
    url: String,
    size: TextUnit,
    label: String?,
    onClick: (() -> Unit)? = null,
) =
    InlineTextContent(Placeholder(size, size, PlaceholderVerticalAlign.Center)) {
        WeiboImage(
            url,
            Modifier.fillMaxSize()
                .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
            contentScale = ContentScale.Fit,
            placeholder = false,
            contentDescription = label,
        )
    }
