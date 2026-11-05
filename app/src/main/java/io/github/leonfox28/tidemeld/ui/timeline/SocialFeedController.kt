package io.github.leonfox28.tidemeld.ui.timeline

import io.github.leonfox28.tidemeld.core.accounts.*
import io.github.leonfox28.tidemeld.core.net.SessionExpiredException
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.data.model.Paged
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.x.XPost
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

sealed interface FeedPost {
    val owner: String
    val key: String
    val date: Instant?

    data class Weibo(override val owner: String, val post: Status) : FeedPost {
        override val key
            get() = "weibo:${post.id}"

        override val date
            get() = post.createdAt
    }

    data class X(override val owner: String, val post: XPost) : FeedPost {
        override val key
            get() = "x:${post.id}"

        override val date
            get() = post.createdAt
    }
}

data class FeedState(
    val items: List<FeedPost> = emptyList(),
    val loading: Boolean = false,
    val errors: Map<String, String> = emptyMap(),
    val hasMore: Boolean = false,
)

/** Per-account cursors and caches; source failure never discards another account's results. */
class SocialFeedController(
    private val accounts: AccountManager,
    private val scope: CoroutineScope,
    private val fetch: suspend (SocialAccount, String?) -> Paged<FeedPost>,
) {
    private data class Source(
        val revision: Long,
        val items: List<FeedPost> = emptyList(),
        val cursor: String? = null,
        val started: Boolean = false,
        val error: String? = null,
    )

    private val sources = mutableMapOf<String, Source>()
    private val mutable = MutableStateFlow(FeedState())
    val state = mutable.asStateFlow()
    private var selection = FeedSelection.All
    private var generation = 0
    private var job: Job? = null
    private var identities = emptyList<Pair<String, Long>>()

    init {
        scope.launch {
            accounts.accounts
                .map { entries -> entries.map { it.key to it.revision } }
                .distinctUntilChanged()
                .drop(1)
                .collect {
                    reconcile()
                    publish()
                }
        }
    }

    fun select(value: FeedSelection) {
        reconcile()
        if (selection != value) {
            generation++
            job?.cancel()
            selection = value
        }
        publish()
        start()
    }

    private fun reconcile() {
        val next = accounts.accounts.value.map { it.key to it.revision }
        if (next == identities) return
        identities = next
        generation++
        job?.cancel()
        sources.entries.removeAll { (key, source) ->
            accounts.find(key)?.revision != source.revision
        }
    }

    fun ownPostChanged(owner: String, post: Status, added: Boolean) {
        if (added) {
            sources[owner]?.let { old ->
                sources[owner] =
                    old.copy(
                        items =
                            listOf(FeedPost.Weibo(owner, post)) +
                                old.items.filterNot { it.key == "weibo:${post.id}" }
                    )
            }
        } else
            sources.replaceAll { _, old ->
                old.copy(items = old.items.filterNot { it.key == "weibo:${post.id}" })
            }
        publish(loading = mutable.value.loading)
    }

    fun start() = run(refresh = false, more = false)

    fun refresh() = run(refresh = true, more = false)

    fun loadMore() = run(refresh = false, more = true)

    fun retry() = run(refresh = false, more = false, retry = true)

    private fun selected() =
        accounts.accounts.value.filter {
            selection.platform == null || it.platform == selection.platform
        }

    private fun run(refresh: Boolean, more: Boolean, retry: Boolean = false) {
        if (job?.isActive == true) return
        val targets =
            selected().filter { account ->
                val source = sources[account.key]
                !account.expired &&
                    (refresh ||
                        source == null ||
                        !source.started ||
                        (retry && source.error != null) ||
                        (more && source.cursor != null && source.error == null))
            }
        if (targets.isEmpty()) {
            publish()
            return
        }
        val ticket = generation
        job = scope.launch {
            publish(loading = true)
            supervisorScope {
                targets
                    .map { account ->
                        async {
                            val old = sources[account.key]
                            val cursor = if (refresh || retry) null else old?.cursor
                            try {
                                val page = fetch(account, cursor)
                                if (
                                    ticket == generation &&
                                        accounts.find(account.key)?.revision == account.revision
                                ) {
                                    val items =
                                        (if (refresh || cursor == null) emptyList()
                                        else old?.items.orEmpty()) + page.items
                                    sources[account.key] =
                                        Source(
                                            account.revision,
                                            items.distinctBy { it.key },
                                            page.nextCursor?.takeIf { it != cursor },
                                            true,
                                        )
                                }
                            } catch (error: WeiboException) {
                                if (
                                    ticket == generation &&
                                        accounts.find(account.key)?.revision == account.revision
                                ) {
                                    sources[account.key] =
                                        (old ?: Source(account.revision)).copy(
                                            started = true,
                                            error = error.message,
                                        )
                                    // Keep the account listed for reauthentication; its other
                                    // sources remain usable.
                                    if (error is SessionExpiredException)
                                        accounts.expire(account.key)
                                }
                            }
                        }
                    }
                    .awaitAll()
            }
            if (ticket == generation) publish()
        }
    }

    private fun publish(loading: Boolean = false) {
        val selected = selected()
        val items =
            selected
                .filterNot { it.expired }
                .flatMap { sources[it.key]?.items.orEmpty() }
                .sortedByDescending { it.date ?: Instant.MIN }
                .distinctBy { it.key }
        val errors =
            selected
                .mapNotNull { account ->
                    val message =
                        if (account.expired) "登录已过期，请重新登录" else sources[account.key]?.error
                    message?.let {
                        account.key to "${account.platform.label} · ${account.name}：$it"
                    }
                }
                .toMap()
        mutable.value =
            FeedState(
                items,
                loading,
                errors,
                selected.any {
                    !it.expired && sources[it.key]?.cursor != null && sources[it.key]?.error == null
                },
            )
    }
}
