package io.github.leonfox28.tidemeld.ui.profile

import io.github.leonfox28.tidemeld.AppGraph
import io.github.leonfox28.tidemeld.core.errors.AppFailure
import io.github.leonfox28.tidemeld.core.net.SessionExpiredException
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.data.model.UserProfile
import io.github.leonfox28.tidemeld.ui.post.recordBlock
import io.github.leonfox28.tidemeld.ui.social.*

/** Captures source account and login revision once, including when opened from search. */
class WeiboProfileControls(private val graph: AppGraph) {
    private val account =
        (graph.session.state.value as? SessionState.SignedIn)?.account?.uid?.let {
            graph.accounts.find("weibo:$it")
        }

    private fun isCurrent() =
        account != null &&
            (graph.session.state.value as? SessionState.SignedIn)?.account?.uid ==
                account.session.account.uid &&
            graph.accounts.find(account.key)?.let {
                it.revision == account.revision && !it.expired
            } == true

    private fun key(uid: String) = "${account?.key}:${account?.revision}:$uid"

    val readStamp
        get() = graph.profileRelationships.readStamp

    fun ingest(profile: UserProfile, started: Long) {
        if (isCurrent()) {
            graph.profileRelationships.ingest(key(profile.user.id), profile.relationship(), started)
            syncBlock(profile.user.id)
        }
    }

    fun state(profile: UserProfile) =
        graph.profileRelationships.state(key(profile.user.id), profile.relationship())

    private fun syncBlock(uid: String) {
        if (!isCurrent()) return
        val blocked = graph.profileRelationships.loadedState(key(uid))?.value?.blocking ?: return
        graph.settings.recordBlock(account!!.key, uid, blocked)
    }

    suspend fun blockUser(uid: String) {
        if (!isCurrent()) throw SessionExpiredException()
        val started = readStamp
        val profile = graph.api.fetchProfile(uid = uid)
        if (!isCurrent()) throw SessionExpiredException()
        ingest(profile, started)
        if (state(profile).value.blocking == true) return
        val action =
            actions(profile)?.more?.firstOrNull { it.id == "block" }
                ?: throw AppFailure("关系状态已变化，请重新打开用户主页")
        action.perform()
    }

    fun actions(profile: UserProfile): ProfileActions? {
        if (!isCurrent() || profile.user.id == account?.session?.account?.uid) return null
        val state = state(profile)
        val uid = profile.user.id
        val change: suspend (Boolean?, Boolean?) -> Unit = { following, blocking ->
            graph.profileRelationships.perform(key(uid), state.value, ::isCurrent) {
                graph.api
                    .changeUserRelationship(uid, following, blocking, ::isCurrent)
                    .relationship()
            }
            syncBlock(uid)
        }
        return profileActions(
            profile.user.screenName,
            state,
            follow = { change(it, null) },
            block = { change(null, it) },
            reposts = null,
            refresh = {
                if (!isCurrent()) throw SessionExpiredException()
                val started = readStamp
                val result = graph.api.fetchProfile(uid = uid)
                if (!isCurrent()) throw SessionExpiredException()
                ingest(result, started)
            },
        )
    }
}

private fun UserProfile.relationship() =
    ProfileRelationship(following, followsMe, blocking = blocking)
