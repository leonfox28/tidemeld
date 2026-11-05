package io.github.leonfox28.tidemeld.core.accounts

import io.github.leonfox28.tidemeld.core.session.SessionController
import io.github.leonfox28.tidemeld.core.session.SessionState
import io.github.leonfox28.tidemeld.core.session.StoredSession
import io.github.leonfox28.tidemeld.core.session.WebCookies
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.yield

/** All saved identities remain signed in; one Weibo account supplies legacy screens and writes. */
class AccountManager(
    initial: List<SocialAccount>,
    private val storage: AccountStorage,
    private val weibo: SessionController,
    private val web: WebCookies,
    private val scope: CoroutineScope,
) {
    private val mutable = MutableStateFlow(initial.distinctBy { it.key })
    val accounts = mutable.asStateFlow()
    private val saving = Mutex()
    private var revision = 0L
    private var changing = false

    init {
        weibo.onLogout = { remove("weibo:$it") }
        weibo.onExpired = { expire("weibo:$it") }
        val legacy = currentWeibo()
        val saved = legacy?.let { find("weibo:${it.account.uid}") }
        if (saved != null) {
            changing = true
            weibo.activate(saved.session.takeUnless { saved.expired })
            changing = false
        } else if (legacy != null) rememberWeibo(legacy)
        else
            mutable.value
                .firstOrNull { it.platform == SocialPlatform.Weibo && !it.expired }
                ?.let { useWeibo(it.key) }
        weibo.jar.addListener {
            if (!changing)
                scope.launch {
                    yield()
                    currentWeibo()?.let { rememberWeibo(it) }
                }
        }
        scope.launch {
            weibo.state.collect { state ->
                yield()
                if (!changing && state is SessionState.SignedIn)
                    currentWeibo()?.let { rememberWeibo(it) }
            }
        }
    }

    private fun currentWeibo(): StoredSession? =
        (weibo.state.value as? SessionState.SignedIn)?.let {
            StoredSession(it.account, weibo.jar.toMap())
        }

    private fun rememberWeibo(session: StoredSession) {
        if (session.cookies.isEmpty()) return
        val key = "weibo:${session.account.uid}"
        val old = mutable.value.firstOrNull { it.key == key }
        upsert(
            SocialAccount(
                SocialPlatform.Weibo,
                session,
                expired = old?.expired ?: false,
                revision = old?.revision ?: ++revision,
            )
        )
    }

    fun find(key: String) = mutable.value.firstOrNull { it.key == key }

    suspend fun add(platform: SocialPlatform, session: StoredSession) {
        val account = SocialAccount(platform, session, revision = ++revision)
        saving.withLock {
            val proposed = replaced(account)
            storage.save(proposed)
            mutable.value = proposed
        }
        if (platform == SocialPlatform.Weibo) useWeibo("weibo:${session.account.uid}")
    }

    /** Switching uses already verified credentials; it never touches another account's cookies. */
    fun useWeibo(key: String): Boolean {
        val account =
            find(key)?.takeIf { it.platform == SocialPlatform.Weibo && !it.expired } ?: return false
        if (
            (weibo.state.value as? SessionState.SignedIn)?.account?.uid ==
                account.session.account.uid && weibo.jar.toMap() == account.session.cookies
        )
            return true
        changing = true
        try {
            weibo.activate(account.session)
        } finally {
            changing = false
        }
        return true
    }

    fun updateCookies(key: String, cookies: Map<String, Map<String, String>>) {
        val current = find(key) ?: return
        upsert(current.copy(session = current.session.copy(cookies = cookies)))
        if (
            current.platform == SocialPlatform.Weibo &&
                (weibo.state.value as? SessionState.SignedIn)?.account?.uid ==
                    current.session.account.uid &&
                weibo.jar.toMap() != cookies
        ) {
            changing = true
            try {
                weibo.jar.replaceAll(cookies)
            } finally {
                changing = false
            }
        }
    }

    suspend fun prepareBrowser(key: String) {
        val account =
            find(key)?.takeUnless { it.expired }
                ?: throw io.github.leonfox28.tidemeld.core.net.SessionExpiredException()
        web.clearDomains(account.platform.domains)
        for ((host, cookies) in account.session.cookies) {
            if (host in account.platform.domains && host in setOf("x.com", "weibo.com", "weibo.cn"))
                web.setCookies(host, cookies)
        }
        if (find(key)?.revision != account.revision)
            throw io.github.leonfox28.tidemeld.core.net.SessionExpiredException()
    }

    fun expire(key: String) {
        val current = find(key) ?: return
        upsert(current.copy(expired = true))
        if (
            current.platform == SocialPlatform.Weibo &&
                (weibo.state.value as? SessionState.SignedIn)?.account?.uid ==
                    current.session.account.uid
        )
            weibo.expire()
    }

    suspend fun remove(key: String) {
        val removed = find(key) ?: return
        changing = true
        try {
            saving.withLock {
                val proposed = mutable.value.filterNot { it.key == key }
                storage.save(proposed)
                mutable.value = proposed
            }
            if (
                removed.platform == SocialPlatform.Weibo &&
                    (weibo.state.value as? SessionState.SignedIn)?.account?.uid ==
                        removed.session.account.uid
            ) {
                val next =
                    mutable.value.firstOrNull { it.platform == SocialPlatform.Weibo && !it.expired }
                weibo.activate(next?.session)
            }
            // Only clear a browser session if it is the identity being removed.
            val cookies =
                web.cookies(
                    if (removed.platform == SocialPlatform.X) "https://x.com/"
                    else "https://weibo.com/"
                )
            val cookieName = if (removed.platform == SocialPlatform.X) "auth_token" else "SUB"
            val host = if (removed.platform == SocialPlatform.X) "x.com" else "weibo.com"
            if (
                cookies[cookieName] != null &&
                    cookies[cookieName] == removed.session.cookies[host]?.get(cookieName)
            ) {
                web.clearDomains(removed.platform.domains)
            }
            persist()
        } finally {
            changing = false
        }
    }

    private fun replaced(account: SocialAccount): List<SocialAccount> =
        mutable.value.let { old ->
            if (old.any { it.key == account.key })
                old.map { if (it.key == account.key) account else it }
            else old + account
        }

    private fun upsert(account: SocialAccount) {
        mutable.value = replaced(account)
        scope.launch {
            try {
                persist()
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (_: Exception) {
                io.github.leonfox28.tidemeld.core.util.devLog("account persistence failed")
            }
        }
    }

    private suspend fun persist() = saving.withLock { storage.save(mutable.value) }
}
