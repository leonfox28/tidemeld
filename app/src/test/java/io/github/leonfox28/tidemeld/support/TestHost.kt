package io.github.leonfox28.tidemeld.support

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import io.github.leonfox28.tidemeld.AppGraph
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.media.LocalImageLoader
import io.github.leonfox28.tidemeld.ui.compose.LocalPicturePicker
import io.github.leonfox28.tidemeld.ui.compose.PicturePicker
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.theme.TidemeldTheme
import io.github.leonfox28.tidemeld.ui.widget.AppSnackbarHost
import io.github.leonfox28.tidemeld.ui.widget.LocalOverlays
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.OverlayHost
import io.github.leonfox28.tidemeld.ui.widget.Overlays

/** [content] with what the app provides around every page, as `TidemeldApp` does. */
@Composable
fun TestHost(
    graph: AppGraph = remember { testGraph() },
    navigator: Navigator = remember { Navigator() },
    picturePicker: PicturePicker = PicturePicker { emptyList() },
    content: @Composable () -> Unit,
) {
    val overlays = remember { Overlays() }
    CompositionLocalProvider(
        LocalAppGraph provides graph,
        LocalNavigator provides navigator,
        LocalSnackbars provides remember { SnackbarHostState() },
        LocalOverlays provides overlays,
        LocalPicturePicker provides picturePicker,
        LocalImageLoader provides graph.imageLoader,
    ) {
        TidemeldTheme(dark = false) {
            content()
            OverlayHost(overlays)
        }
    }
}

/** [content] with the app's snackbars showing over it, as a page's scaffold shows them. */
@Composable
fun WithSnackbars(content: @Composable () -> Unit) {
    Scaffold(snackbarHost = { AppSnackbarHost() }) { padding ->
        Box(Modifier.padding(padding)) { content() }
    }
}
