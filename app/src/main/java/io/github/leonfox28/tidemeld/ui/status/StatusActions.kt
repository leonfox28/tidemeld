package io.github.leonfox28.tidemeld.ui.status

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import io.github.leonfox28.tidemeld.data.model.PicInfo
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.ui.interactions.rememberStatusWrites
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.webview.weiboSearchUrl
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.openExternally
import io.github.leonfox28.tidemeld.ui.widget.status.StatusCardActions
import io.github.leonfox28.tidemeld.ui.widget.text.StatusLink

/** Reuses native media viewers; account-only actions open sign-in before any API call. */
@Composable
fun rememberGuestStatusCardActions(): StatusCardActions {
    val api = io.github.leonfox28.tidemeld.LocalAppGraph.current.api
    val navigator = LocalNavigator.current
    val base = rememberStatusCardActions()
    return remember(navigator, base) {
        fun login() = navigator.push(Route.Login)
        base.copy(
            onLike = { login() },
            onOpen = { login() },
            onExpand = { login() },
            onUser = { login() },
            onRepost = { login() },
            onDelete = null,
            onPicture = { pics, index, _ ->
                navigator.push(Route.Viewer(pics, index, weiboPhotoMotion(api, null)))
            },
            onLink = { link ->
                when (link) {
                    is StatusLink.Mention -> login()
                    is StatusLink.Topic ->
                        openSearchResults(navigator, "#${link.topic}#", asGuest = true)
                    else -> base.onLink?.invoke(link)
                }
            },
        )
    }
}

/** What tapping parts of a status card (or a comment) does throughout the app. */
@Composable
fun rememberStatusCardActions(): StatusCardActions {
    val api = io.github.leonfox28.tidemeld.LocalAppGraph.current.api
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    val writes = rememberStatusWrites()
    return remember(navigator, context, writes, api) {
        fun openExternally(url: String) = context.openExternally(url, snackbars, scope)

        fun openStatus(status: Status) = navigator.push(Route.StatusDetail(status.id, status))

        fun viewPictures(pics: List<PicInfo>, index: Int, status: Status? = null) =
            navigator.push(Route.Viewer(pics, index, weiboPhotoMotion(api, status?.id)))

        StatusCardActions(
            onOpen = ::openStatus,
            onLink = { link ->
                when (link) {
                    is StatusLink.Web -> openExternally(link.url.toString())
                    is StatusLink.Video ->
                        navigator.push(Route.Video(weiboVideoRequest(api, link.video)))
                    // Mentions carry only the name.
                    is StatusLink.Mention -> navigator.push(Route.ProfileByName(link.screenName))
                    is StatusLink.Topic -> openSearchResults(navigator, "#${link.topic}#")
                    is StatusLink.Image ->
                        if (link.pics.isNotEmpty()) {
                            viewPictures(link.pics, 0)
                        } else {
                            openExternally(link.url.toString())
                        }
                }
            },
            onUser = { navigator.push(Route.Profile(it.id, it)) },
            // The detail page has the full text of long posts.
            onExpand = ::openStatus,
            onPicture = ::viewPictures,
            onVideo = { status, index ->
                navigator.push(Route.Video(weiboVideoRequest(api, status, index)))
            },
            onRepost = { writes.repost(it) },
            onDelete = { writes.delete(it) },
        )
    }
}

/** Opens the results of searching for [query]; `#话题#` searches the topic. */
fun openSearchResults(navigator: Navigator, query: String, asGuest: Boolean = false) {
    val trimmed = query.trim()
    if (trimmed.isNotEmpty()) {
        navigator.push(
            if (asGuest) Route.Web(weiboSearchUrl(trimmed)) else Route.SearchResults(trimmed)
        )
    }
}
