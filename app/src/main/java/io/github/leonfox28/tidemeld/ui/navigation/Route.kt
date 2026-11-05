package io.github.leonfox28.tidemeld.ui.navigation

import io.github.leonfox28.tidemeld.core.media.PhotoMotion
import io.github.leonfox28.tidemeld.core.media.VideoRequest
import io.github.leonfox28.tidemeld.data.model.PicInfo
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.WeiboUser
import io.github.leonfox28.tidemeld.ui.comments.CommentThread

/**
 * A page of the app. The tabs share one, [Home]; every other page goes on top of it. Like
 * go_router's `extra` in the Flutter app, a route may carry what the previous page already has,
 * such as the status that was tapped.
 */
sealed interface Route {
    /** The four tabs. */
    data object Home : Route

    data object Login : Route

    data object Accounts : Route

    data class PlatformLogin(
        val platform: io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
    ) : Route

    data class ForAccount(val key: String, val page: Route) : Route

    /** A status and its comments; [initial] shows until the full status loads. */
    data class XDetail(
        val owner: String,
        val id: String,
        val initial: io.github.leonfox28.tidemeld.data.x.XPost? = null,
    ) : Route

    data class StatusDetail(val id: String, val initial: Status? = null) : Route

    /** A comment and its replies ("楼中楼"). */
    data class Comments(val thread: CommentThread) : Route

    /** Platform-neutral pictures with an optional motion capability. */
    data class Viewer(val pics: List<PicInfo>, val index: Int, val motion: PhotoMotion? = null) :
        Route

    /** A platform adapter supplies a request to the shared player. */
    data class Video(val request: VideoRequest) : Route

    data class Profile(val uid: String, val initial: WeiboUser? = null) : Route

    /** A profile by screen name, as @mentions name users. */
    data class ProfileByName(val name: String) : Route

    data class SearchResults(val query: String) : Route

    /** A web page in the in-app browser; [onClose] runs once the user leaves it. */
    data class AccountWeb(val account: String, val url: String) : Route

    data class Web(val url: String, val onClose: (() -> Unit)? = null) : Route

    /** Writing a new post. */
    data object Compose : Route

    /** The text size, on a slider over sample posts. */
    data object TextSize : Route

    data object About : Route

    /** The libraries tidemeld is built on, and their licences. */
    data object Licenses : Route

    /** Debug builds only. */
    data object Diagnostics : Route
}
