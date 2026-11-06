package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.ui.widget.PicGrid

/** Shared attachment layout; adapters supply only content and navigation. */
@Composable
fun PostMedia(
    items: List<MixedMedia>,
    total: Int? = null,
    compact: Boolean = false,
    preferVideoCover: Boolean = true,
    sensitive: Boolean = false,
    identity: String? = null,
    onOpen: ((Int) -> Unit)? = null,
) {
    if (items.isEmpty()) return
    var revealed by remember(identity, items, sensitive) { mutableStateOf(false) }
    if (sensitive && !revealed) {
        Surface(
            shape = MaterialTheme.shapes.medium,
            color = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            Column(
                Modifier.fillMaxWidth().padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("媒体已隐藏", style = MaterialTheme.typography.titleSmall)
                Text("平台将此媒体标记为敏感内容。默认不加载图片或视频。", style = MaterialTheme.typography.bodySmall)
                OutlinedButton(onClick = { revealed = true }) { Text("显示此条媒体") }
            }
        }
        return
    }
    Column {
        val video = (items.singleOrNull() as? MixedMedia.Video)?.video
        if (compact) PostCommentMedia(items, onOpen)
        else if (preferVideoCover && video != null) VideoCover(video, onOpen?.let { { it(0) } })
        else PicGrid(items, total = total ?: items.size, onClick = onOpen)
        if (sensitive) TextButton(onClick = { revealed = false }) { Text("重新隐藏媒体") }
    }
}
