package io.github.leonfox28.tidemeld.ui.post

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.core.errors.*
import io.github.leonfox28.tidemeld.ui.widget.*

/** One editor surface. Adapters own draft state, supported options and submission. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PostEditor(
    title: String,
    hint: String,
    text: TextFieldValue,
    onTextChange: (TextFieldValue) -> Unit,
    sending: Boolean,
    canSend: Boolean,
    onSend: () -> Unit,
    fullPage: Boolean = false,
    sendLabel: String = "发送",
    context: String? = null,
    failure: AppFailure? = null,
    notice: String? = null,
    progress: String? = null,
    onClose: () -> Unit = {},
    onRecover: ((FailureRecovery) -> Unit)? = null,
    attachments: @Composable () -> Unit = {},
    options: @Composable () -> Unit = {},
) {
    val focus = remember { FocusRequester() }
    BackHandler(enabled = sending) {}
    val sendButton: @Composable () -> Unit = {
        Button(onClick = onSend, enabled = canSend && !sending) {
            if (sending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            else Text(sendLabel)
        }
    }
    val body: @Composable () -> Unit = {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            context?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
            OutlinedTextField(
                text,
                onTextChange,
                Modifier.fillMaxWidth().focusRequester(focus),
                enabled = !sending,
                placeholder = { Text(hint) },
                minLines = if (fullPage) 5 else 3,
                maxLines = if (fullPage) Int.MAX_VALUE else 10,
            )
            if (failure != null && !failure.isCancelled) FailureNotice(failure, onRecover)
            notice?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            progress?.let {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    Text(it, style = MaterialTheme.typography.bodySmall)
                }
            }
            attachments()
            options()
            if (!fullPage)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    sendButton()
                }
        }
    }
    if (fullPage) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(title) },
                    navigationIcon = { CloseButton(onClick = { if (!sending) onClose() }) },
                    actions = { Box(Modifier.padding(end = 12.dp)) { sendButton() } },
                )
            },
            snackbarHost = { AppSnackbarHost() },
        ) { padding ->
            BoxWithConstraints(Modifier.fillMaxSize().imePadding().padding(padding)) {
                Column(
                    Modifier.fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(readingPadding(maxWidth, PaddingValues(16.dp)))
                ) {
                    body()
                }
            }
        }
    } else {
        Column(
            Modifier.fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
        ) {
            body()
        }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
}
