package io.github.leonfox28.tidemeld.ui.interactions

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.BrokenImage
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.media.LocalImageLoader
import io.github.leonfox28.tidemeld.core.net.CaptchaRequiredException
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.ui.compose.DraftPicture
import io.github.leonfox28.tidemeld.ui.widget.AppAlertDialog
import io.github.leonfox28.tidemeld.ui.widget.OverlaySheet
import io.github.leonfox28.tidemeld.ui.widget.Overlays

/** A comment or reply the user is writing: text, and a picture. */
data class CommentDraft(val text: String = "", val picture: DraftPicture? = null) {
    /** A picture can go without text, as on weibo.com. */
    val canSend: Boolean
        get() = text.isNotBlank() || picture != null
}

/**
 * Opens a sheet to write a comment or reply on status [statusId], which [send] posts when the user
 * taps 发送, with the pid of its picture once uploaded. Returns true once it is sent.
 *
 * What the user writes is kept in [drafts] under [draftKey] until it is sent, so closing the sheet
 * loses nothing.
 */
suspend fun Overlays.showCommentComposer(
    statusId: String,
    hint: String,
    drafts: MutableMap<String, CommentDraft>,
    draftKey: String,
    send: suspend (text: String, pid: String?) -> Unit,
): Boolean =
    show<Boolean> { close -> CommentComposer(statusId, hint, drafts, draftKey, send, close) }
        ?: false

@Composable
private fun CommentComposer(
    statusId: String,
    hint: String,
    drafts: MutableMap<String, CommentDraft>,
    draftKey: String,
    send: suspend (text: String, pid: String?) -> Unit,
    close: (Boolean?) -> Unit,
) {
    val graph = LocalAppGraph.current
    io.github.leonfox28.tidemeld.ui.post.PostComposer(
        hint,
        drafts,
        draftKey,
        send,
        close,
        attachments =
            io.github.leonfox28.tidemeld.ui.post.PostAttachments(
                allowed = { graph.api.allowsCommentPicture(statusId) },
                upload = { graph.api.uploadPicture(graph.pictures.read(it.uri)) },
                unavailableMessage = "这条微博的评论不能带图",
            ),
    )
}

/** The text field of a composer sheet, focused as it opens. */
@Composable
internal fun ComposerField(
    text: String,
    onChange: (String) -> Unit,
    hint: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val focus = remember { FocusRequester() }
    OutlinedTextField(
        text,
        onChange,
        modifier.fillMaxWidth().focusRequester(focus),
        enabled = enabled,
        placeholder = { Text(hint) },
        minLines = 3,
        maxLines = 6,
    )
    LaunchedEffect(Unit) { focus.requestFocus() }
}

/** A sheet's send button, showing progress while it sends. */
@Composable
internal fun SendButton(label: String, sending: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled && !sending) {
        if (sending) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        } else {
            Text(label)
        }
    }
}

/**
 * A picked picture, square, with a way to take it out ([onRemove]; none while it can't be), dimmed
 * with progress while [uploading].
 */
@Composable
fun PictureThumb(
    uri: String,
    size: Dp,
    uploading: Boolean,
    onRemove: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.colorScheme
    val pixels = with(LocalDensity.current) { size.roundToPx() }
    val context = LocalContext.current
    Box(modifier.size(size)) {
        AsyncImage(
            remember(uri, pixels) { ImageRequest.Builder(context).data(uri).size(pixels).build() },
            contentDescription = null,
            imageLoader = LocalImageLoader.current,
            modifier =
                Modifier.fillMaxSize()
                    .clip(RoundedCornerShape(4.dp))
                    .background(colors.surfaceContainerHighest),
            contentScale = ContentScale.Crop,
            error = rememberVectorPainter(Icons.Outlined.BrokenImage),
        )
        if (uploading) {
            Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.38f)),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
            }
        }
        if (onRemove != null) {
            FilledTonalIconButton(
                onClick = onRemove,
                modifier = Modifier.align(Alignment.TopEnd).padding(2.dp).size(22.dp),
            ) {
                Icon(Icons.Filled.Close, contentDescription = "移除", Modifier.size(14.dp))
            }
        }
    }
}

/**
 * Why sending what the user wrote failed, under it, with a way to take the check when Weibo asks
 * for one: the user takes it, then sends again themselves (PLAN §2).
 */
@Composable
fun SendError(error: WeiboException, onVerify: (url: String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            error.message,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
        )
        if (error is CaptchaRequiredException) {
            TextButton(onClick = { onVerify(error.url.toString()) }) { Text("去验证") }
        }
    }
}

/**
 * Offers to delete something the user wrote, and asks [question] before it goes. Returns true when
 * they confirmed.
 */
suspend fun Overlays.confirmDelete(question: String = "确定删除这条评论吗？"): Boolean {
    val chosen =
        show<Boolean> { close ->
            OverlaySheet(close) { dismiss ->
                Column(Modifier.navigationBarsPadding()) {
                    ListItem(
                        headlineContent = { Text("删除") },
                        leadingContent = { Icon(Icons.Outlined.Delete, contentDescription = null) },
                        modifier = Modifier.clickable { dismiss(true) },
                    )
                    ListItem(
                        headlineContent = { Text("取消") },
                        leadingContent = { Icon(Icons.Filled.Close, contentDescription = null) },
                        modifier = Modifier.clickable { dismiss(false) },
                    )
                }
            }
        }
    if (chosen != true) return false
    return show<Boolean> { close ->
        AppAlertDialog(
            onDismissRequest = { close(null) },
            text = { Text(question) },
            confirmButton = { TextButton(onClick = { close(true) }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { close(false) }) { Text("取消") } },
        )
    } == true
}
