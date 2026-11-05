package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.leonfox28.tidemeld.core.util.formatCount
import io.github.leonfox28.tidemeld.ui.widget.CommentBar

/** Bound callbacks carry the source account; unsupported actions are absent. */
data class PostInteractionActions(
    val reposts: Int = 0,
    val comments: Int = 0,
    val likes: Int = 0,
    val liked: Boolean = false,
    val reposted: Boolean = false,
    val likePending: Boolean = false,
    val repostPending: Boolean = false,
    val onRepost: (() -> Unit)? = null,
    val onComment: (() -> Unit)? = null,
    val onLike: (() -> Unit)? = null,
)

@Composable
fun PostInteractionBar(actions: PostInteractionActions) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        PostCount(
            Icons.Filled.Repeat,
            actions.reposts,
            "转发",
            actions.reposted,
            actions.repostPending,
            actions.onRepost,
        )
        PostCount(
            Icons.Outlined.ChatBubbleOutline,
            actions.comments,
            "评论",
            false,
            false,
            actions.onComment,
        )
        PostCount(
            if (actions.liked) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
            actions.likes,
            "赞",
            actions.liked,
            actions.likePending,
            actions.onLike,
        )
    }
}

@Composable
private fun RowScope.PostCount(
    icon: ImageVector,
    count: Int,
    label: String,
    selected: Boolean,
    pending: Boolean,
    action: (() -> Unit)?,
) {
    val tint =
        if (selected) MaterialTheme.colorScheme.primary
        else MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        Modifier.weight(1f)
            .then(
                if (action != null || pending)
                    Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        if (!pending) action?.invoke()
                    }
                else Modifier
            )
            .semantics {
                contentDescription = if (count > 0) "$label $count" else label
                if (pending || selected) stateDescription = if (pending) "处理中" else "已$label"
                if (pending) disabled()
            }
            .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(16.dp), tint = tint)
        Spacer(Modifier.width(4.dp))
        Text(if (count > 0) formatCount(count) else label, fontSize = 13.sp, color = tint)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PostDetailActions(actions: PostInteractionActions, modifier: Modifier = Modifier) {
    CommentBar(
        hint = "写评论…",
        onClick = { actions.onComment?.invoke() },
        modifier = modifier,
        trailing = {
            CompositionLocalProvider(LocalRippleConfiguration provides null) {
                Row {
                    TextButton(
                        onClick = { actions.onRepost?.invoke() },
                        enabled = actions.onRepost != null && !actions.repostPending,
                    ) {
                        Icon(Icons.Filled.Repeat, null)
                        Spacer(Modifier.width(8.dp))
                        Text(if (actions.reposted) "已转发" else "转发")
                    }
                    val color =
                        if (actions.liked) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    TextButton(
                        onClick = { actions.onLike?.invoke() },
                        enabled = actions.onLike != null && !actions.likePending,
                    ) {
                        Icon(
                            if (actions.liked) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                            null,
                            tint = color,
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            if (actions.likes > 0) formatCount(actions.likes) else "赞",
                            color = color,
                        )
                    }
                }
            }
        },
    )
}
