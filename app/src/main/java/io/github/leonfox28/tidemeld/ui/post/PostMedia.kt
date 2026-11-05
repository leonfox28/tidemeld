package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.runtime.Composable
import io.github.leonfox28.tidemeld.data.model.MixedMedia
import io.github.leonfox28.tidemeld.ui.widget.PicGrid

/** Shared attachment layout; adapters supply only content and navigation. */
@Composable
fun PostMedia(
    items: List<MixedMedia>,
    total: Int? = null,
    compact: Boolean = false,
    preferVideoCover: Boolean = true,
    onOpen: ((Int) -> Unit)? = null,
) {
    if (items.isEmpty()) return
    val video = (items.singleOrNull() as? MixedMedia.Video)?.video
    if (compact) PostCommentMedia(items, onOpen)
    else if (preferVideoCover && video != null) VideoCover(video, onOpen?.let { { it(0) } })
    else PicGrid(items, total = total ?: items.size, onClick = onOpen)
}
