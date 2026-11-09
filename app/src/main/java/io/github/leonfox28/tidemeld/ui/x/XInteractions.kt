package io.github.leonfox28.tidemeld.ui.x

import io.github.leonfox28.tidemeld.core.accounts.*
import io.github.leonfox28.tidemeld.core.net.*
import io.github.leonfox28.tidemeld.data.model.Paged
import io.github.leonfox28.tidemeld.data.x.*
import io.github.leonfox28.tidemeld.ui.social.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class XInteractionState(
    val metrics: XMetrics,
    val busy: Boolean = false,
    val version: Long = 0,
)

enum class XWrite {
    Like,
    Repost,
    Reply,
    Quote,
}

/** State belongs to an account and the original post, including cards showing a repost. */
class XInteractions(
    private val accounts: AccountManager,
    private val api: XWebApi?,
    val relationships: ProfileRelationships = ProfileRelationships(),
) {
    private val mutable = MutableStateFlow<Map<String, XInteractionState>>(emptyMap())
    val states = mutable.asStateFlow()
    val drafts = mutableMapOf<String, io.github.leonfox28.tidemeld.ui.interactions.CommentDraft>()
    var readStamp = 0L
        private set

    fun key(owner: String, id: String) = "$owner:${accounts.find(owner)?.revision}:$id"

    fun state(
        owner: String,
        post: XPost,
        snapshot: Map<String, XInteractionState> = mutable.value,
    ) = snapshot[key(owner, post.originalId)] ?: XInteractionState(post.metrics)

    fun ingest(account: SocialAccount, posts: List<XPost>, started: Long) {
        if (accounts.find(account.key)?.revision != account.revision) return
        val updated = mutable.value.toMutableMap()
        fun accept(post: XPost) {
            val key = key(account.key, post.originalId)
            val old = updated[key]
            if (old?.busy != true && (old?.version ?: 0) <= started)
                updated[key] = XInteractionState(post.metrics, version = old?.version ?: 0)
            post.quote?.let(::accept)
        }
        posts.forEach(::accept)
        mutable.value = updated
    }

    private fun account(owner: String) =
        accounts.find(owner)?.takeIf { it.platform == SocialPlatform.X && !it.expired }
            ?: throw SessionExpiredException()

    private fun service() = api ?: throw WeiboApiException("X 接口配置不可用")

    private fun cookies(account: SocialAccount): (Map<String, Map<String, String>>) -> Unit =
        { value ->
            if (accounts.find(account.key)?.revision == account.revision)
                accounts.updateCookies(account.key, value)
        }

    suspend fun conversation(owner: String, id: String, cursor: String?): XConversation {
        val account = account(owner)
        val started = readStamp
        try {
            val page = service().conversation(account.session, id, cursor, cookies(account))
            if (accounts.find(owner)?.revision != account.revision) throw SessionExpiredException()
            ingest(account, page.ancestors + listOfNotNull(page.post) + page.replies.items, started)
            return page
        } catch (error: SessionExpiredException) {
            if (accounts.find(owner)?.revision == account.revision) accounts.expire(owner)
            throw error
        }
    }

    suspend fun profile(owner: String, user: XProfileUser): XUserProfile =
        read(owner) { account, api ->
            api.profile(account.session, user, cookies(account))
        }

    suspend fun refreshRelationship(owner: String, uid: String, revision: Long? = null) {
        val account = account(owner)
        if (revision != null && revision != account.revision) throw SessionExpiredException()
        if (uid == account.session.account.uid) return
        val started = relationships.readStamp
        val result =
            read(owner) { source, api -> api.relationship(source.session, uid, cookies(source)) }
        relationships.ingest(key(owner, uid), result.presentation(), started)
    }

    fun relationshipActions(owner: String, user: XProfileUser, failed: Boolean): ProfileActions? {
        val uid = user.id ?: return null
        val account = runCatching { account(owner) }.getOrNull() ?: return null
        if (uid == account.session.account.uid) return null
        val key = key(owner, uid)
        val refresh: suspend () -> Unit = { refreshRelationship(owner, uid, account.revision) }
        val state =
            relationships.loadedState(key)
                ?: return if (failed)
                    ProfileActions(ProfileAction("refresh", "刷新状态", perform = refresh))
                else ProfileActions(busy = true)
        val current = {
            accounts.find(owner)?.let { it.revision == account.revision && !it.expired } == true
        }
        val change: suspend (XUserAction) -> Unit = { action ->
            relationships.perform(key, state.value, current) {
                try {
                    service()
                        .changeRelationship(account.session, uid, action, cookies(account), current)
                        .presentation()
                } catch (error: SessionExpiredException) {
                    if (current()) accounts.expire(owner)
                    throw error
                }
            }
        }
        return profileActions(
            user.name ?: user.handle ?: "此用户",
            state,
            follow = { change(XUserAction.Follow(it)) },
            block = { change(XUserAction.Block(it)) },
            reposts = { change(XUserAction.Reposts(it)) },
            refresh = refresh,
        )
    }

    suspend fun userPosts(owner: String, uid: String, cursor: String?): Paged<XPost> {
        val started = readStamp
        return read(owner) { account, api ->
            api.userPosts(account.session, uid, cursor, cookies(account)).also {
                ingest(account, it.items, started)
            }
        }
    }

    private suspend fun <T> read(owner: String, action: suspend (SocialAccount, XWebApi) -> T): T {
        val account = account(owner)
        try {
            val result = action(account, service())
            if (
                accounts.find(owner)?.let { it.revision == account.revision && !it.expired } != true
            )
                throw SessionExpiredException()
            return result
        } catch (error: SessionExpiredException) {
            if (accounts.find(owner)?.revision == account.revision) accounts.expire(owner)
            throw error
        }
    }

    suspend fun write(owner: String, post: XPost, action: XWrite, text: String = ""): String? {
        val account = account(owner)
        val isCurrent = {
            accounts.find(owner)?.let { it.revision == account.revision && !it.expired } == true
        }
        val key = key(owner, post.originalId)
        val before = state(owner, post)
        if (before.busy) throw WeiboApiException("正在处理，请稍候")
        fun put(value: XInteractionState) {
            mutable.value = mutable.value + (key to value)
        }
        put(before.copy(busy = true, version = ++readStamp))
        var metrics = before.metrics
        try {
            val service = service()
            val id =
                when (action) {
                    XWrite.Like -> {
                        service.like(
                            account.session,
                            post.originalId,
                            !metrics.liked,
                            cookies(account),
                            isCurrent,
                        )
                        metrics =
                            metrics.copy(
                                liked = !metrics.liked,
                                likes =
                                    (metrics.likes + if (metrics.liked) -1 else 1).coerceAtLeast(0),
                            )
                        null
                    }
                    XWrite.Repost -> {
                        service.repost(
                            account.session,
                            post.originalId,
                            !metrics.reposted,
                            cookies(account),
                            isCurrent,
                        )
                        metrics =
                            metrics.copy(
                                reposted = !metrics.reposted,
                                reposts =
                                    (metrics.reposts + if (metrics.reposted) -1 else 1)
                                        .coerceAtLeast(0),
                            )
                        null
                    }
                    XWrite.Reply,
                    XWrite.Quote -> {
                        val created =
                            service.publish(
                                account.session,
                                post,
                                text,
                                action == XWrite.Quote,
                                cookies(account),
                                isCurrent,
                            )
                        if (action == XWrite.Reply)
                            metrics = metrics.copy(replies = metrics.replies + 1)
                        created
                    }
                }
            if (accounts.find(owner)?.revision != account.revision)
                throw WeiboApiException("账号已变更，请刷新后检查操作结果")
            put(XInteractionState(metrics, version = ++readStamp))
            return id
        } catch (error: Exception) {
            if (
                error is SessionExpiredException &&
                    accounts.find(owner)?.revision == account.revision
            )
                accounts.expire(owner)
            put(before.copy(version = ++readStamp))
            throw error
        }
    }
}

private fun XUserRelationship.presentation() =
    ProfileRelationship(following, followsYou, requested, blocking, showsReposts)
