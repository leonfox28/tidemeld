package io.github.leonfox28.tidemeld.ui.social

import io.github.leonfox28.tidemeld.core.errors.AppFailure
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class ProfileRelationship(
    val following: Boolean,
    val followsYou: Boolean = false,
    val requested: Boolean = false,
    val blocking: Boolean? = null,
    val showsReposts: Boolean? = null,
) {
    val label: String?
        get() =
            when {
                blocking == true -> "已拉黑"
                requested -> "已申请关注"
                following && followsYou -> "互相关注"
                following -> "已关注"
                followsYou -> "关注了你"
                else -> null
            }
}

data class ProfileRelationshipState(
    val value: ProfileRelationship,
    val busy: Boolean = false,
    val needsRefresh: Boolean = false,
    val version: Long = 0,
)

/** Account and login-revision scoped; late reads cannot overwrite an acknowledged write. */
class ProfileRelationships {
    private val mutable = MutableStateFlow<Map<String, ProfileRelationshipState>>(emptyMap())
    val states = mutable.asStateFlow()
    var readStamp = 0L
        private set

    fun loadedState(key: String) = mutable.value[key]

    fun state(key: String, fallback: ProfileRelationship) =
        mutable.value[key] ?: ProfileRelationshipState(fallback)

    private fun put(key: String, value: ProfileRelationshipState) {
        mutable.value += key to value
    }

    fun ingest(key: String, value: ProfileRelationship, started: Long) {
        val old = mutable.value[key]
        if (old?.busy == true || (old?.version ?: 0) > started) return
        put(key, ProfileRelationshipState(value, version = old?.version ?: 0))
    }

    suspend fun perform(
        key: String,
        expected: ProfileRelationship,
        isCurrent: () -> Boolean,
        change: suspend () -> ProfileRelationship,
    ) {
        val before = state(key, expected)
        if (!isCurrent()) throw AppFailure("账号已变更，请重新打开主页")
        if (before.busy) return
        if (before.needsRefresh || before.value != expected) throw AppFailure("关系状态已变化，请刷新后再操作")
        put(key, ProfileRelationshipState(before.value, busy = true, version = ++readStamp))
        try {
            val value = change()
            if (!isCurrent()) throw AppFailure("账号已变更，请刷新后检查操作结果")
            put(key, ProfileRelationshipState(value, version = ++readStamp))
        } catch (error: Exception) {
            put(
                key,
                ProfileRelationshipState(before.value, needsRefresh = true, version = ++readStamp),
            )
            throw error
        }
    }
}
