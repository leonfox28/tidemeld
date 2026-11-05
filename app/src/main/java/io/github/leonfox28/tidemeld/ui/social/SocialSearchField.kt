package io.github.leonfox28.tidemeld.ui.social

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.ui.widget.ReadingWidth

@Composable
fun SocialSearchField(
    hint: String,
    focusRequested: Boolean,
    onFocused: () -> Unit,
    onSearch: (String) -> Unit,
) {
    val focus = LocalFocusManager.current
    val requester = remember { FocusRequester() }
    val text = rememberTextFieldState()
    val colors = MaterialTheme.colorScheme
    fun search() {
        val query = text.text.toString().trim()
        if (query.isEmpty()) return
        focus.clearFocus()
        onSearch(query)
    }
    LaunchedEffect(focusRequested) {
        if (focusRequested) {
            requester.requestFocus()
            onFocused()
        }
    }
    // Over the list's column, not spread across a wide window.
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Surface(
            Modifier.widthIn(max = ReadingWidth)
                .fillMaxWidth()
                .padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 4.dp),
            shape = CircleShape,
            color = colors.surfaceContainerHigh,
        ) {
            Row(
                Modifier.height(56.dp).padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Filled.Search,
                    contentDescription = null,
                    modifier = Modifier.padding(horizontal = 12.dp),
                )
                BasicTextField(
                    text,
                    Modifier.weight(1f).focusRequester(requester),
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface),
                    lineLimits = TextFieldLineLimits.SingleLine,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    onKeyboardAction = { search() },
                    cursorBrush = SolidColor(colors.primary),
                    decorator = { field ->
                        Box(contentAlignment = Alignment.CenterStart) {
                            if (text.text.isEmpty()) {
                                Text(
                                    hint,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = colors.onSurfaceVariant,
                                )
                            }
                            field()
                        }
                    },
                )
                if (text.text.isNotEmpty()) {
                    IconButton(onClick = { text.clearText() }) {
                        Icon(Icons.Filled.Close, contentDescription = "清除")
                    }
                } else {
                    Spacer(Modifier.width(12.dp))
                }
            }
        }
    }
}
