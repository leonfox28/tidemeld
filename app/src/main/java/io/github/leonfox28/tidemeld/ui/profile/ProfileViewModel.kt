package io.github.leonfox28.tidemeld.ui.profile

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.core.paging.PagedController
import io.github.leonfox28.tidemeld.data.api.WeiboApi
import io.github.leonfox28.tidemeld.data.model.Paged
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.UserProfile
import io.github.leonfox28.tidemeld.ui.interactions.OpenLists
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** The statuses of user [uid], paged by number. */
class UserStatusesController(private val api: WeiboApi, val uid: String, scope: CoroutineScope) :
    PagedController<Status>(scope) {
    override suspend fun fetchPage(cursor: String?): Paged<Status> =
        api.fetchUserStatuses(uid = uid, page = cursor?.toInt() ?: 1)

    override fun idOf(item: Status) = item.id
}

/** The profile as loaded, or why it couldn't be. */
data class ProfileLoad(val profile: UserProfile? = null, val error: WeiboException? = null)

/**
 * What a profile page holds: the user with [uid], or else the one named [screenName], and their
 * statuses. Opened by uid it loads both at once; by name only, the statuses wait for the profile.
 */
class ProfileViewModel(
    private val uid: String?,
    private val screenName: String?,
    private val api: WeiboApi,
    private val openLists: OpenLists,
    graph: io.github.leonfox28.tidemeld.AppGraph? = null,
) : ViewModel() {
    val controls = graph?.let(::WeiboProfileControls)
    private var generation = 0
    private val _profile = MutableStateFlow(ProfileLoad())
    val profile: StateFlow<ProfileLoad> = _profile.asStateFlow()

    var statuses by mutableStateOf<UserStatusesController?>(null)
        private set

    init {
        uid?.let(::startStatuses)
        reload()
    }

    fun reload() {
        _profile.update { it.copy(error = null) }
        val ticket = ++generation
        viewModelScope.launch {
            try {
                loadProfile(ticket)
            } catch (e: WeiboException) {
                if (ticket == generation) _profile.update { it.copy(error = e) }
            }
        }
    }

    private suspend fun loadProfile(ticket: Int) {
        val started = controls?.readStamp ?: 0L
        val result =
            api.fetchProfile(uid = _profile.value.profile?.user?.id ?: uid, screenName = screenName)
        if (ticket != generation) return
        _profile.value = ProfileLoad(result)
        controls?.ingest(result, started)
        if (statuses == null) startStatuses(result.user.id)
    }

    private fun startStatuses(uid: String) {
        val list = UserStatusesController(api, uid, viewModelScope)
        // So the user's own posts and reposts show, and deleted ones go.
        addCloseable(openLists.userStatuses.add(uid, list))
        statuses = list.also { it.start() }
    }

    /**
     * Loads the profile and the statuses again.
     *
     * @throws WeiboException on failure, what was shown staying, for the caller to report.
     */
    suspend fun refresh() =
        kotlinx.coroutines.supervisorScope {
            val ticket = ++generation
            val details = async { loadProfile(ticket) }
            val content = async { statuses?.refresh() }
            val results = listOf(details, content).map { runCatching { it.await() } }
            results.forEach { it.getOrThrow() }
            Unit
        }
}
