package io.github.leonfox28.tidemeld.ui.navigation

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.staticCompositionLocalOf

/** The stack of pages, [Route.Home] at the bottom. */
class Navigator(
    val backStack: SnapshotStateList<Route> = mutableStateListOf(Route.Home),
    private val account: String? = null,
) {
    fun forAccount(key: String) = Navigator(backStack, key)

    fun push(route: Route) {
        val global =
            route == Route.Home ||
                route == Route.Accounts ||
                route == Route.Login ||
                route is Route.PlatformLogin ||
                route is Route.ForAccount
        backStack.add(if (account != null && !global) Route.ForAccount(account, route) else route)
    }

    /** Closes the top page, unless it's the tabs. */
    fun pop() {
        if (backStack.size <= 1) return
        val closed = backStack.removeAt(backStack.lastIndex)
        ((if (closed is Route.ForAccount) closed.page else closed) as? Route.Web)?.onClose?.invoke()
    }
}

val LocalNavigator = staticCompositionLocalOf<Navigator> { error("No Navigator provided") }
