package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.errors.AppFailure
import io.github.leonfox28.tidemeld.core.util.devLog
import io.github.leonfox28.tidemeld.ui.compose.DraftPicture
import io.github.leonfox28.tidemeld.ui.compose.LocalPicturePicker
import io.github.leonfox28.tidemeld.ui.compose.PickerUnavailableException
import io.github.leonfox28.tidemeld.ui.interactions.*
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.widget.OverlaySheet
import io.github.leonfox28.tidemeld.ui.widget.recover
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Optional attachment capability, supplied by the platform without leaking its API into UI. */
data class PostAttachments(
    val allowed: suspend () -> Boolean,
    val upload: suspend (DraftPicture) -> String,
    val unavailableMessage: String,
)

@Composable
fun PostComposer(
    hint: String,
    drafts: MutableMap<String, CommentDraft>,
    draftKey: String,
    send: suspend (text: String, pid: String?) -> Unit,
    close: (Boolean?) -> Unit,
    attachments: PostAttachments? = null,
    context: String? = null,
) {
    val picker = LocalPicturePicker.current
    val navigator = LocalNavigator.current
    val scope = rememberCoroutineScope()
    var draft by remember { mutableStateOf(drafts[draftKey] ?: CommentDraft()) }
    var editorText by
        remember(draftKey) {
            mutableStateOf(TextFieldValue(draft.text, TextRange(draft.text.length)))
        }
    fun keep(changed: CommentDraft) {
        draft = changed
        drafts[draftKey] = changed
    }
    var sending by remember { mutableStateOf(false) }
    var uploading by remember { mutableStateOf(false) }
    // Whether the platform permits attachments here, once asked.
    var pictureAllowed by remember { mutableStateOf<Boolean?>(null) }
    var asking by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<Exception?>(null) }

    fun pick() = scope.launch {
        val support = attachments ?: return@launch
        notice = null
        error = null
        // Asked only when the user wants a picture, so opening the sheet
        // requests nothing (PLAN §2).
        if (pictureAllowed == null) {
            asking = true
            try {
                pictureAllowed = support.allowed()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                // The platform validates attachment support again when sending.
                devLog("Attachment capability check failed: ${e.javaClass.simpleName}")
            } finally {
                asking = false
            }
        }
        if (pictureAllowed == false) {
            notice = support.unavailableMessage
            return@launch
        }
        val uris =
            try {
                picker.pick(1)
            } catch (_: PickerUnavailableException) {
                notice = "无法打开相册"
                return@launch
            }
        uris.firstOrNull()?.let { keep(draft.copy(picture = DraftPicture(it))) }
    }

    OverlaySheet(close, canDismiss = !sending) { dismiss ->
        fun submit() = scope.launch {
            sending = true
            notice = null
            error = null
            try {
                var picture = draft.picture
                if (picture != null && picture.pid == null) {
                    uploading = true
                    val pid = attachments?.upload?.invoke(picture) ?: throw AppFailure("此操作不支持图片")
                    // Kept, so sending again after a failure doesn't upload it again.
                    picture = picture.copy(pid = pid)
                    keep(draft.copy(picture = picture))
                    uploading = false
                }
                send(draft.text.trim(), picture?.pid)
                drafts -= draftKey
                sending = false
                dismiss(true)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                error = e
                sending = false
                uploading = false
            }
        }

        PostEditor(
            title = "写评论",
            hint = hint,
            text = editorText,
            onTextChange = {
                editorText = it
                keep(draft.copy(text = it.text))
            },
            sending = sending,
            canSend = draft.canSend,
            onSend = { submit() },
            context = context,
            failure = error?.let(AppFailure::of),
            notice = notice,
            onRecover = { recovery ->
                dismiss(null)
                navigator.recover(recovery)
            },
            attachments = {
                val picture = draft.picture
                if (picture != null) {
                    PictureThumb(
                        picture.uri,
                        size = 64.dp,
                        uploading = uploading,
                        onRemove = if (sending) null else ({ keep(draft.copy(picture = null)) }),
                    )
                } else if (attachments != null) {
                    IconButton(
                        onClick = { pick() },
                        enabled = !sending && !asking && pictureAllowed != false,
                    ) {
                        if (asking) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Outlined.AddPhotoAlternate, contentDescription = "添加图片")
                        }
                    }
                }
            },
        )
    }
}
