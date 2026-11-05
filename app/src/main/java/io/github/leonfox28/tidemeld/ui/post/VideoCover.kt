package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.media.WeiboImage
import io.github.leonfox28.tidemeld.core.util.formatDuration
import io.github.leonfox28.tidemeld.data.model.VideoInfo
import io.github.leonfox28.tidemeld.ui.widget.*

@Composable
fun VideoCover(video: VideoInfo, onClick: (() -> Unit)?) {
    // Portrait videos are cropped square to keep the timeline compact.
    val ratio = (video.aspectRatio ?: (16f / 9)).coerceIn(1f, 16f / 9)
    Box(
        Modifier.fillMaxWidth()
            .aspectRatio(ratio)
            .semantics { contentDescription = "播放视频" }
            .clip(RoundedCornerShape(6.dp))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
    ) {
        val cover = video.coverUrl
        if (cover != null) WeiboImage(cover, Modifier.fillMaxSize())
        else
            Box(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerHighest)
            )
        PlayIcon(52.dp, Modifier.align(Alignment.Center))
        val duration = video.duration
        if (duration != null && duration > 0) {
            MediaBadge(formatDuration(duration), Modifier.align(Alignment.BottomEnd).padding(6.dp))
        }
    }
}
