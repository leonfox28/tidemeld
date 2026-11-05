package io.github.leonfox28.tidemeld.ui.social

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.media.WeiboImage

@Composable
fun SocialNoticeRow(
    author: String,
    activity: String,
    time: String?,
    onOpen: (() -> Unit)?,
    avatar: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        Modifier.fillMaxWidth()
            .then(if (onOpen != null) Modifier.clickable(onClick = onOpen) else Modifier)
            .padding(16.dp, 12.dp)
    ) {
        Box(Modifier.size(32.dp)) { avatar() }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = muted, fontWeight = FontWeight.Medium)) {
                        append(author)
                    }
                    append(" $activity")
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyMedium,
            )
            time?.let {
                Spacer(Modifier.height(2.dp))
                Text(it, style = MaterialTheme.typography.bodySmall, color = muted)
            }
            Spacer(Modifier.height(8.dp))
            content()
        }
    }
}

@Composable
fun PostSummary(author: String?, text: String, thumbnail: String?, onOpen: (() -> Unit)?) {
    val colors = MaterialTheme.colorScheme
    Surface(
        Modifier.fillMaxWidth()
            .then(if (onOpen != null) Modifier.clickable(onClick = onOpen) else Modifier),
        shape = RoundedCornerShape(6.dp),
        color = colors.surfaceContainerHigh,
    ) {
        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (thumbnail != null) {
                WeiboImage(thumbnail, Modifier.size(48.dp).clip(RoundedCornerShape(4.dp)))
                Spacer(Modifier.width(8.dp))
            }
            Text(
                buildAnnotatedString {
                    if (author != null)
                        withStyle(SpanStyle(fontWeight = FontWeight.Medium)) { append("@$author：") }
                    append(text)
                },
                Modifier.weight(1f),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodySmall,
                color = colors.onSurfaceVariant,
            )
        }
    }
}
