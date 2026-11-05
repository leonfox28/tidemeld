package io.github.leonfox28.tidemeld.ui.x

import io.github.leonfox28.tidemeld.core.accounts.*
import io.github.leonfox28.tidemeld.core.net.*
import io.github.leonfox28.tidemeld.data.x.*
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
class XInteractions(private val accounts: AccountManager, private val api: XWebApi?) {
    private val mutable = MutableStateFlow<Map<String, XInteractionState>>(emptyMap())
    val states = mutable.asStateFlow()
    val drafts = mutableMapOf<String, String>()
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
            ingest(account, listOfNotNull(page.post) + page.replies.items, started)
            return page
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
