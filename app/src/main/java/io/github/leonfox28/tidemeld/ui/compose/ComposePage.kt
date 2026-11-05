package io.github.leonfox28.tidemeld.ui.compose

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.errors.AppFailure
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.ui.interactions.PictureThumb
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.post.PostEditor
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.recover
import io.github.leonfox28.tidemeld.ui.widget.showMessage
import kotlinx.coroutines.launch

/**
 * Writes a new post: text, up to nine pictures, and who can see it.
 *
 * Nothing goes to Weibo until the user taps 发送; the pictures upload then, one at a time. The draft
 * outlives the page (`AppGraph.composeDraft`).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ComposePage() {
    val graph = LocalAppGraph.current
    val controller = graph.composeDraft
    val draft by controller.draft.collectAsStateWithLifecycle()
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val picker = LocalPicturePicker.current
    val focusManager = LocalFocusManager.current
    val scope = rememberCoroutineScope()
    var text by remember {
        val initial = controller.draft.value.text
        mutableStateOf(TextFieldValue(initial, TextRange(initial.length)))
    }
    var sending by remember { mutableStateOf(false) }
    // The picture going up, from 0, while sending.
    var uploading by remember { mutableStateOf<Int?>(null) }
    var error by remember { mutableStateOf<WeiboException?>(null) }

    fun pick() = scope.launch {
        val room = MAX_DRAFT_PICTURES - controller.draft.value.pictures.size
        if (room <= 0) return@launch
        val uris =
            try {
                picker.pick(room)
            } catch (_: PickerUnavailableException) {
                snackbars.showMessage("无法打开相册", scope)
                return@launch
            }
        val left = controller.addPictures(uris)
        // Pickers without a limit, on older Android, let the user pick more.
        if (left > 0) {
            snackbars.showMessage("最多 $MAX_DRAFT_PICTURES 张图片，多选的 $left 张没有加上", scope)
        }
    }

    fun send() = scope.launch {
        focusManager.clearFocus()
        sending = true
        error = null
        try {
            controller.send(onUpload = { uploading = it })
            snackbars.showMessage("已发送", graph.appScope)
            navigator.pop()
        } catch (e: WeiboException) {
            error = e
        } finally {
            sending = false
            uploading = null
        }
    }

    PostEditor(
        title = "发微博",
        hint = "分享新鲜事…",
        text = text,
        onTextChange = {
            text = it
            if (it.text != controller.draft.value.text) controller.setText(it.text)
        },
        sending = sending,
        canSend = draft.canSend,
        onSend = { send() },
        fullPage = true,
        failure = error?.let(AppFailure::of),
        progress = uploading?.let { "正在上传图片 ${it + 1}/${draft.pictures.size}" },
        onClose = { navigator.pop() },
        onRecover = { navigator.recover(it) },
        attachments = {
            PictureGrid(draft.pictures, uploading, !sending, { pick() }, controller::removePicture)
        },
        options = {
            VisibilityButton(
                draft.visibility,
                onChange = if (sending) null else controller::setVisibility,
            )
        },
    )
}

private val Gap = 4.dp

/** The picked pictures in rows of three, with a tile to add more while there is room. */
@Composable
private fun PictureGrid(
    pictures: List<DraftPicture>,
    uploading: Int?,
    enabled: Boolean,
    onAdd: () -> Unit,
    onRemove: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val side: Dp = (maxWidth - Gap * 2) / 3
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(Gap),
            verticalArrangement = Arrangement.spacedBy(Gap),
            maxItemsInEachRow = 3,
        ) {
            pictures.forEachIndexed { i, picture ->
                PictureThumb(
                    picture.uri,
                    size = side,
                    uploading = i == uploading,
                    onRemove = if (enabled) ({ onRemove(i) }) else null,
                )
            }
            if (pictures.size < MAX_DRAFT_PICTURES) {
                Surface(
                    Modifier.size(side)
                        .clip(RoundedCornerShape(4.dp))
                        .clickable(enabled = enabled, onClick = onAdd),
                    color = MaterialTheme.colorScheme.surfaceContainerHighest,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            Icons.Outlined.AddPhotoAlternate,
                            contentDescription = "添加图片",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}
