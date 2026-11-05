package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.ui.widget.ReadingWidth
import io.github.leonfox28.tidemeld.ui.widget.TagLabel
import io.github.leonfox28.tidemeld.ui.widget.WideCardFrom

/** Platform adapters supply content and callbacks; layout never looks up an account or API. */
@Composable
fun PostCard(
    modifier: Modifier = Modifier,
    detail: Boolean = false,
    activity: String? = null,
    onOpen: (() -> Unit)? = null,
    header: @Composable () -> Unit,
    body: @Composable () -> Unit,
    aside: (@Composable () -> Unit)? = null,
    footer: @Composable () -> Unit = {},
) {
    Column(
        modifier
            .then(if (!detail && onOpen != null) Modifier.clickable(onClick = onOpen) else Modifier)
            .padding(start = 16.dp, top = 12.dp, end = 16.dp, bottom = if (detail) 12.dp else 0.dp)
    ) {
        if (!detail && activity != null) {
            PostActivity(activity)
            Spacer(Modifier.height(8.dp))
        }
        val main: @Composable () -> Unit = {
            Column {
                header()
                Spacer(Modifier.height(8.dp))
                body()
            }
        }
        if (detail) {
            main()
            aside?.let {
                Spacer(Modifier.height(8.dp))
                it()
            }
        } else PostCardLayout(main, aside, footer)
    }
}

@Composable
fun PostHeader(
    name: String,
    metadata: String,
    tags: List<String> = emptyList(),
    onAuthor: (() -> Unit)? = null,
    avatar: @Composable () -> Unit,
    badge: @Composable () -> Unit = {},
    menu: @Composable () -> Unit = {},
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        avatar()
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    name,
                    Modifier.weight(1f, fill = false)
                        .then(
                            if (onAuthor != null) Modifier.clickable(onClick = onAuthor)
                            else Modifier
                        ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.titleSmall,
                )
                badge()
            }
            if (metadata.isNotEmpty())
                Text(
                    metadata,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
        }
        tags.forEachIndexed { i, tag ->
            if (i > 0) Spacer(Modifier.width(4.dp))
            TagLabel(tag)
        }
        menu()
    }
}

@Composable
fun QuotedPost(onOpen: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Box(
            Modifier.testTag("retweet")
                .then(if (onOpen != null) Modifier.clickable(onClick = onOpen) else Modifier)
                .padding(10.dp)
        ) {
            content()
        }
    }
}

/** Beside media the text keeps to about a phone's width of line; the media takes the rest. */
private val WideMainWidth = 400.dp
private val WideAsideGap = 24.dp

/** With no media, the longest line the text runs to. */
private val WideMainAloneWidth = ReadingWidth

/** Under media beside the text, as above it at the top of the card. */
private val WideAsideBottom = 12.dp

/** Between the text and the media under it. */
private val NarrowAsideGap = 8.dp

/**
 * A timeline card's text ([main]), its counts ([footer]) and its media ([aside]), if any. Narrow,
 * they go one under another. Wide, the media goes to the right of the text and counts; the counts
 * come right after the text, or at the foot of the card if the media runs further down, so they
 * never leave a gap under it.
 */
@Composable
private fun PostCardLayout(
    main: @Composable () -> Unit,
    aside: (@Composable () -> Unit)?,
    footer: @Composable () -> Unit,
) {
    Layout(listOf(main, footer, aside ?: {})) { (mains, footers, asides), constraints ->
        val width = constraints.maxWidth
        // The card's own padding counts towards the width a card is given.
        val wide = width + 32.dp.roundToPx() >= WideCardFrom.roundToPx()
        val hasAside = aside != null
        val mainWidth =
            if (!wide) width
            else minOf(width, (if (hasAside) WideMainWidth else WideMainAloneWidth).roundToPx())
        val exact = Constraints.fixedWidth(mainWidth)
        val mainPlaced = mains.single().measure(exact)
        val footerPlaced = footers.single().measure(exact)
        val asideWidth = if (wide) maxOf(0, width - WideAsideGap.roundToPx() - mainWidth) else width
        val asidePlaced = asides.singleOrNull()?.measure(Constraints(maxWidth = asideWidth))
        if (wide) {
            val height =
                maxOf(
                    mainPlaced.height + footerPlaced.height,
                    asidePlaced?.let { it.height + WideAsideBottom.roundToPx() } ?: 0,
                )
            layout(width, height) {
                mainPlaced.place(0, 0)
                footerPlaced.place(0, height - footerPlaced.height)
                asidePlaced?.place(mainWidth + WideAsideGap.roundToPx(), 0)
            }
        } else {
            val gap = if (asidePlaced != null) NarrowAsideGap.roundToPx() else 0
            val asideHeight = asidePlaced?.height ?: 0
            layout(width, mainPlaced.height + gap + asideHeight + footerPlaced.height) {
                mainPlaced.place(0, 0)
                asidePlaced?.place(0, mainPlaced.height + gap)
                footerPlaced.place(0, mainPlaced.height + gap + asideHeight)
            }
        }
    }
}

@Composable
private fun PostActivity(label: String) {
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    // The icons of the counts under a card.
    val icon =
        when {
            label.contains("赞") -> Icons.Outlined.ThumbUp
            label.contains("评论") -> Icons.Outlined.ChatBubbleOutline
            else -> null
        }
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp), tint = color)
            Spacer(Modifier.width(6.dp))
        }
        Text(
            label,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            style = MaterialTheme.typography.bodySmall,
            color = color,
        )
    }
}
