package io.github.leonfox28.tidemeld.ui.post

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.core.util.devLog
import io.github.leonfox28.tidemeld.ui.compose.DraftPicture
import io.github.leonfox28.tidemeld.ui.compose.LocalPicturePicker
import io.github.leonfox28.tidemeld.ui.compose.PickerUnavailableException
import io.github.leonfox28.tidemeld.ui.interactions.*
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.widget.OverlaySheet
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
    var error by remember { mutableStateOf<WeiboException?>(null) }

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
            } catch (e: WeiboException) {
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
                    val pid =
                        attachments?.upload?.invoke(picture)
                            ?: throw io.github.leonfox28.tidemeld.core.net.WeiboApiException(
                                "此操作不支持图片"
                            )
                    // Kept, so sending again after a failure doesn't upload it again.
                    picture = picture.copy(pid = pid)
                    keep(draft.copy(picture = picture))
                    uploading = false
                }
                send(draft.text.trim(), picture?.pid)
                drafts -= draftKey
                sending = false
                dismiss(true)
            } catch (e: WeiboException) {
                error = e
                sending = false
                uploading = false
            }
        }

        Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp)) {
            context?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }
            ComposerField(
                draft.text,
                onChange = { keep(draft.copy(text = it)) },
                hint = hint,
                enabled = !sending,
            )
            error?.let { e ->
                SendError(
                    e,
                    // The sheet would stay over the page; the draft stays too.
                    onVerify = { url ->
                        dismiss(null)
                        navigator.push(Route.Web(url))
                    },
                )
            }
            notice?.let {
                Text(
                    it,
                    modifier = Modifier.padding(top = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
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
                Spacer(Modifier.weight(1f))
                SendButton("发送", sending = sending, enabled = draft.canSend) { submit() }
            }
        }
    }
}
