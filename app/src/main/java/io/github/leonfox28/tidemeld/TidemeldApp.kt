package io.github.leonfox28.tidemeld

import android.app.UiModeManager
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.LocalActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.scene.DialogSceneStrategy
import androidx.navigation3.scene.SinglePaneSceneStrategy
import io.github.leonfox28.tidemeld.core.media.LocalImageLoader
import io.github.leonfox28.tidemeld.core.settings.ThemeMode
import io.github.leonfox28.tidemeld.ui.auth.LoginPage
import io.github.leonfox28.tidemeld.ui.comments.CommentRepliesPage
import io.github.leonfox28.tidemeld.ui.compose.ComposePage
import io.github.leonfox28.tidemeld.ui.compose.LocalPicturePicker
import io.github.leonfox28.tidemeld.ui.compose.PicturePicker
import io.github.leonfox28.tidemeld.ui.compose.rememberGalleryPicker
import io.github.leonfox28.tidemeld.ui.debug.DiagnosticsPage
import io.github.leonfox28.tidemeld.ui.media.ImageViewerPage
import io.github.leonfox28.tidemeld.ui.media.VideoPlayerPage
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.PageStack
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.notifications.UnreadChecks
import io.github.leonfox28.tidemeld.ui.profile.ProfilePage
import io.github.leonfox28.tidemeld.ui.search.SearchResultsPage
import io.github.leonfox28.tidemeld.ui.settings.AboutPage
import io.github.leonfox28.tidemeld.ui.settings.LicensesPage
import io.github.leonfox28.tidemeld.ui.settings.TextSizePage
import io.github.leonfox28.tidemeld.ui.shell.HomeShell
import io.github.leonfox28.tidemeld.ui.status.StatusDetailPage
import io.github.leonfox28.tidemeld.ui.theme.DarkColors
import io.github.leonfox28.tidemeld.ui.theme.KeepTextSize
import io.github.leonfox28.tidemeld.ui.theme.LightColors
import io.github.leonfox28.tidemeld.ui.theme.LocalTextSize
import io.github.leonfox28.tidemeld.ui.theme.TidemeldTheme
import io.github.leonfox28.tidemeld.ui.theme.isDark
import io.github.leonfox28.tidemeld.ui.webview.WebPage
import io.github.leonfox28.tidemeld.ui.widget.LocalOverlays
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.OverlayHost
import io.github.leonfox28.tidemeld.ui.widget.Overlays

/**
 * The whole app, in the theme and text size the user has chosen.
 *
 * @param picturePicker tests swap in their own.
 */
@Composable
fun TidemeldApp(
    graph: AppGraph,
    navigator: Navigator = remember { Navigator() },
    picturePicker: PicturePicker = rememberGalleryPicker(),
) {
    val settings by graph.settings.settings.collectAsStateWithLifecycle()
    val dark = settings.themeMode.isDark()
    val overlays = remember { Overlays() }
    WindowFor(settings.themeMode, dark)
    CompositionLocalProvider(
        LocalAppGraph provides graph,
        LocalNavigator provides navigator,
        LocalSnackbars provides remember { SnackbarHostState() },
        LocalOverlays provides overlays,
        LocalPicturePicker provides picturePicker,
        LocalImageLoader provides graph.imageLoader,
        // On top of the system's font size, for every page and snackbar;
        // dialogs, sheets and menus apply it again (KeepTextSize).
        LocalDensity provides settings.textSize.applyTo(LocalDensity.current),
        LocalTextSize provides settings.textSize,
    ) {
        // Out here, where it stays for as long as the app: under a page pushed
        // over the tabs, they leave the composition.
        UnreadChecks()
        TidemeldTheme(dark = dark) {
            PageStack(
                backStack = navigator.backStack,
                onBack = navigator::pop,
                dark = dark,
                entryDecorators =
                    listOf(
                        rememberSaveableStateHolderNavEntryDecorator(),
                        rememberViewModelStoreNavEntryDecorator(),
                    ),
                // The image viewer is a dialog over the page it opened from.
                sceneStrategies = listOf(DialogSceneStrategy(), SinglePaneSceneStrategy()),
                entryProvider = pages,
            )
            OverlayHost(overlays)
        }
    }
}

private val FullScreenDialog =
    DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)

/** What each page shows. */
private val pages: (Route) -> NavEntry<Route> = entryProvider {
    entry<Route.Home> { HomeShell() }
    entry<Route.Login> { io.github.leonfox28.tidemeld.ui.auth.PlatformPickerPage() }
    entry<Route.Accounts> { io.github.leonfox28.tidemeld.ui.auth.AccountsPage() }
    entry<Route.PlatformLogin> { LoginPage(it.platform) }
    entry<Route.ForAccount> { route ->
        val root = LocalAppGraph.current
        val accounts by root.accounts.accounts.collectAsStateWithLifecycle()
        val scoped =
            accounts
                .firstOrNull { it.key == route.key && !it.expired }
                ?.let { root.forAccount(it.key) }
        if (scoped != null) {
            val navigator = LocalNavigator.current
            CompositionLocalProvider(
                LocalAppGraph provides scoped,
                LocalNavigator provides
                    remember(navigator, route.key) { navigator.forAccount(route.key) },
            ) {
                if (route.page is Route.Web)
                    io.github.leonfox28.tidemeld.ui.webview.AccountWebPage(
                        route.key,
                        route.page.url,
                    )
                else pages(route.page).Content()
            }
        } else io.github.leonfox28.tidemeld.ui.auth.PlatformPickerPage()
    }
    entry<Route.StatusDetail> { StatusDetailPage(it.id, it.initial) }
    entry<Route.Comments> { CommentRepliesPage(it.thread) }
    entry<Route.Viewer>(metadata = DialogSceneStrategy.dialog(FullScreenDialog)) {
        KeepTextSize { ImageViewerPage(it.pics, it.index, it.statusId) }
    }
    entry<Route.Video> { VideoPlayerPage(it.id, it.index, it.initial) }
    entry<Route.Profile> { ProfilePage(uid = it.uid, initial = it.initial) }
    entry<Route.ProfileByName> { ProfilePage(screenName = it.name) }
    entry<Route.SearchResults> { SearchResultsPage(it.query) }
    entry<Route.Web> { WebPage(it.url) }
    entry<Route.AccountWeb> {
        io.github.leonfox28.tidemeld.ui.webview.AccountWebPage(it.account, it.url)
    }
    entry<Route.TextSize> { TextSizePage() }
    entry<Route.About> { AboutPage() }
    entry<Route.Licenses> { LicensesPage() }
    entry<Route.Compose> { ComposePage() }
    entry<Route.Diagnostics> { if (BuildConfig.DEBUG) DiagnosticsPage() }
}

/**
 * Edge to edge, with status bar icons to suit the theme where no app bar sets them, as on the tabs
 * or once a page's app bar has scrolled away.
 *
 * The window behind the pages is in the theme's background too: it shows through as one page fades
 * into the next. Its own, from the manifest's theme, is the system's light or dark as of when the
 * activity was created, which dark mode in tidemeld's settings, or the system's switched on since,
 * leaves light (the activity handles uiMode changes itself).
 *
 * From Android 12, the system also has the app's own [mode] for the window it shows while the app
 * starts next, in place of its own light or dark.
 */
@Composable
private fun WindowFor(mode: ThemeMode, dark: Boolean) {
    val activity = LocalActivity.current as? ComponentActivity ?: return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        LaunchedEffect(activity, mode) {
            activity
                .getSystemService(UiModeManager::class.java)
                .setApplicationNightMode(mode.nightMode)
        }
    }
    DisposableEffect(activity, dark) {
        activity.enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT) { dark },
            navigationBarStyle = SystemBarStyle.auto(LightScrim, DarkScrim) { dark },
        )
        val background = if (dark) DarkColors.background else LightColors.background
        activity.window.setBackgroundDrawable(ColorDrawable(background.toArgb()))
        onDispose {}
    }
}

/** For [UiModeManager.setApplicationNightMode]; the system's own, unless chosen. */
private val ThemeMode.nightMode
    get() =
        when (this) {
            ThemeMode.System -> UiModeManager.MODE_NIGHT_AUTO
            ThemeMode.Light -> UiModeManager.MODE_NIGHT_NO
            ThemeMode.Dark -> UiModeManager.MODE_NIGHT_YES
        }

// The scrims enableEdgeToEdge() puts behind three-button navigation.
private val LightScrim = Color.argb(0xe6, 0xFF, 0xFF, 0xFF)
private val DarkScrim = Color.argb(0x80, 0x1b, 0x1b, 0x1b)
