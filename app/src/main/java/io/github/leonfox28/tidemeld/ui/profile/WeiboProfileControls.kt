package io.github.leonfox28.tidemeld.ui.profile

import io.github.leonfox28.tidemeld.AppGraph
import io.github.leonfox28.tidemeld.core.net.SessionExpiredException
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.data.model.UserProfile
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
        if (isCurrent())
            graph.profileRelationships.ingest(key(profile.user.id), profile.relationship(), started)
    }

    fun state(profile: UserProfile) =
        graph.profileRelationships.state(key(profile.user.id), profile.relationship())

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
