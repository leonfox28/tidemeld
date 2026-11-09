package io.github.leonfox28.tidemeld.ui.social

import androidx.compose.foundation.background
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.util.formatCount
import io.github.leonfox28.tidemeld.ui.post.PostAvatar
import io.github.leonfox28.tidemeld.ui.widget.TagLabel

data class ProfileCount(val label: String, val value: Long)

data class ProfilePresentation(
    val name: String?,
    val avatarUrl: String?,
    val coverUrl: String?,
    val counts: List<ProfileCount>,
    val relation: String?,
    val verification: String?,
    val description: String?,
    val loading: Boolean,
    val failure: String?,
)

@Composable
fun SocialProfileHeader(
    profile: ProfilePresentation,
    onRetry: () -> Unit,
    badge: @Composable () -> Unit = {},
    details: @Composable () -> Unit = {},
    actions: ProfileActions? = null,
) {
    val colors = MaterialTheme.colorScheme
    val typography = MaterialTheme.typography
    val muted = colors.onSurfaceVariant
    Column(Modifier.fillMaxWidth()) {
        profile.coverUrl?.let { WeiboImage(it, Modifier.fillMaxWidth().height(120.dp)) }
        Column(Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PostAvatar(profile.avatarUrl, profile.name ?: "头像", size = 64.dp)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (profile.name != null) {
                            Text(
                                profile.name,
                                modifier = Modifier.weight(1f, fill = false),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = typography.titleLarge,
                            )
                        } else if (profile.loading) {
                            LinePlaceholder(120.dp, typography.titleLarge)
                        }
                        badge()
                        if (actions == null && profile.relation != null) {
                            Spacer(Modifier.width(8.dp))
                            TagLabel(profile.relation)
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    if (actions == null) {
                        if (!profile.loading) ProfileCounts(profile.counts)
                        else LinePlaceholder(160.dp, typography.bodyMedium)
                    } else profile.relation?.let { TagLabel(it) }
                }
                actions?.let { SocialProfileActions(it) }
            }
            if (actions != null) {
                Spacer(Modifier.height(8.dp))
                ProfileCounts(profile.counts)
            }
            profile.verification?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, style = typography.bodySmall, color = muted)
            }
            profile.description?.let {
                Spacer(Modifier.height(8.dp))
                Text(it)
            }
            details()
            if (profile.loading) {
                Spacer(Modifier.height(8.dp))
                LinePlaceholder(240.dp, typography.bodyMedium)
            }
            if (profile.failure != null) {
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        profile.failure,
                        modifier = Modifier.weight(1f),
                        style = typography.bodySmall,
                        color = colors.error,
                    )
                    TextButton(onClick = onRetry) { Text("重试") }
                }
            }
        }
    }
}

/**
 * A grey bar holding the place of a line of text in [style] until the profile arrives, so the
 * header keeps its height when it does.
 */
@Composable
private fun LinePlaceholder(width: Dp, style: TextStyle) {
    Box(Modifier.width(width)) {
        // Invisible, for the height of a line.
        Text(" ", style = style)
        Box(
            Modifier.matchParentSize()
                .padding(vertical = 3.dp)
                .background(
                    MaterialTheme.colorScheme.surfaceContainerHighest,
                    RoundedCornerShape(4.dp),
                )
        )
    }
}

/** Following, follower and status counts. Display only: follower lists aren't part of tidemeld. */
@Composable
private fun ProfileCounts(counts: List<ProfileCount>) {
    val colors = MaterialTheme.colorScheme
    Text(
        buildAnnotatedString {
            counts.forEachIndexed { i, (label, count) ->
                if (i > 0) append("    ")
                withStyle(SpanStyle(color = colors.onSurface, fontWeight = FontWeight.SemiBold)) {
                    append(formatCount(count))
                }
                append(" $label")
            }
        },
        style = MaterialTheme.typography.bodyMedium,
        color = colors.onSurfaceVariant,
    )
}
