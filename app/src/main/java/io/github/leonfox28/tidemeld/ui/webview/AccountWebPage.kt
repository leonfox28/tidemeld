package io.github.leonfox28.tidemeld.ui.webview

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import kotlinx.coroutines.CancellationException

/** No request is made until the browser holds this card's account. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountWebPage(owner: String, url: String) {
    val graph = LocalAppGraph.current
    val navigator = LocalNavigator.current
    var ready by remember(owner) { mutableStateOf(false) }
    var error by remember(owner) { mutableStateOf<String?>(null) }
    LaunchedEffect(owner) {
        try {
            graph.accounts.prepareBrowser(owner)
            ready = true
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            error = "账号不可用，请返回账号管理重新登录"
        }
    }
    if (ready) WebPage(url)
    else
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("准备账号") },
                    navigationIcon = {
                        IconButton(onClick = navigator::pop) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                        }
                    },
                )
            }
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                if (error != null) Text(error.orEmpty()) else CircularProgressIndicator()
            }
        }
}
