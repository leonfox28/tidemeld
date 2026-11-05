package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.util.formatCount
import io.github.leonfox28.tidemeld.data.model.MixedMedia

/** Shared comment geometry; platform adapters supply content and account-bound actions. */
@Composable
fun PostComment(
    author: String,
    metadata: String,
    modifier: Modifier = Modifier,
    isAuthor: Boolean = false,
    onReply: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    avatar: @Composable () -> Unit,
    content: @Composable () -> Unit,
    like: @Composable () -> Unit,
    replies: (@Composable () -> Unit)? = null,
    below: (@Composable () -> Unit)? = null,
) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier
            .fillMaxWidth()
            .then(
                if (onReply != null || onLongClick != null)
                    Modifier.combinedClickable(onClick = onReply ?: {}, onLongClick = onLongClick)
                else Modifier
            )
            .padding(16.dp, 12.dp)
    ) {
        Box(Modifier.size(32.dp)) { avatar() }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    author,
                    Modifier.weight(1f, fill = false),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                    color = muted,
                    fontWeight = FontWeight.Medium,
                )
                if (isAuthor) {
                    Spacer(Modifier.width(4.dp))
                    Text(
                        "博主",
                        Modifier.background(
                                MaterialTheme.colorScheme.primaryContainer,
                                RoundedCornerShape(3.dp),
                            )
                            .padding(horizontal = 4.dp, vertical = 1.dp),
                        fontSize = 10.sp,
                        lineHeight = 14.sp,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    metadata,
                    Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodySmall,
                    color = muted,
                )
                like()
            }
            if (replies != null) {
                Spacer(Modifier.height(8.dp))
                replies()
            }
            if (below != null) {
                Spacer(Modifier.height(8.dp))
                below()
            }
        }
    }
}

@Composable
fun PostCommentLike(count: Int, liked: Boolean, onToggle: (() -> Unit)?, pending: Boolean = false) {
    val color =
        if (liked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        Modifier.clickable(
                remember { MutableInteractionSource() },
                indication = null,
                onClick = { if (!pending) onToggle?.invoke() },
            )
            .semantics { contentDescription = if (count > 0) "赞 $count" else "赞" }
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (liked) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
            null,
            Modifier.size(14.dp),
            tint = color,
        )
        Spacer(Modifier.width(3.dp))
        Text(
            if (count > 0) formatCount(count) else "赞",
            style = MaterialTheme.typography.bodySmall,
            color = color,
        )
    }
}

@Composable
fun PostCommentThread(count: Int, onOpen: () -> Unit, content: @Composable () -> Unit) {
    val style = MaterialTheme.typography.bodyMedium.let { it.copy(lineHeight = it.fontSize * 1.4f) }
    Surface(
        onClick = onOpen,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column(Modifier.padding(8.dp)) {
            content()
            Text("共${count}条回复 >", style = style, color = MaterialTheme.colorScheme.primary)
        }
    }
}

/** Compact mixed attachments. The adapter owns viewers and source refresh. */
@Composable
fun PostCommentMedia(items: List<MixedMedia>, onOpen: ((Int) -> Unit)?) {
    val settings by LocalAppGraph.current.settings.settings.collectAsStateWithLifecycle()
    val pixels = settings.imageQuality.listPixels(96f, LocalDensity.current.density)
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        items.forEachIndexed { index, item ->
            val url =
                when (item) {
                    is MixedMedia.Pic -> item.pic.variantFor(pixels).url
                    is MixedMedia.Video -> item.video.coverUrl
                }
            Box(
                Modifier.size(96.dp)
                    .testTag("media")
                    .clip(RoundedCornerShape(4.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .then(if (onOpen != null) Modifier.clickable { onOpen(index) } else Modifier),
                contentAlignment = Alignment.Center,
            ) {
                if (url != null) WeiboImage(url, Modifier.fillMaxSize())
                if (item is MixedMedia.Video)
                    Icon(Icons.Filled.PlayCircle, "播放视频", Modifier.size(32.dp), tint = Color.White)
            }
        }
    }
}
