package io.github.leonfox28.tidemeld.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.leonfox28.tidemeld.ui.widget.BackButton
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.openExternally

object ContentTerms {
    const val version = "2026-11-12"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TermsPage(onAccept: (() -> Unit)? = null) {
    val context = LocalContext.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    val text =
        remember(context) {
            runCatching { context.assets.open("TERMS.md").bufferedReader().use { it.readText() } }
                .getOrNull()
        }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("使用条款") },
                navigationIcon = { if (onAccept == null) BackButton() },
            )
        }
    ) { padding ->
        Column(
            Modifier.fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (text == null) Text("使用条款暂时无法读取，请重新打开应用。")
            else {
                for (paragraph in text.split("\n\n")) {
                    Text(
                        paragraph.replace(Regex("^#{1,2} "), ""),
                        style =
                            if (paragraph.startsWith("#")) MaterialTheme.typography.titleMedium
                            else MaterialTheme.typography.bodyMedium,
                    )
                }
                TextButton(
                    onClick = {
                        context.openExternally(
                            "$REPO_URL/blob/main/docs/PRIVACY.md",
                            snackbars,
                            scope,
                        )
                    }
                ) {
                    Text("隐私政策")
                }
                if (onAccept != null) {
                    Button(onClick = onAccept, modifier = Modifier.fillMaxWidth()) { Text("同意并继续") }
                    Text(
                        "点击“同意并继续”表示你接受以上条款。如不同意，请停止使用叠澜。",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}
