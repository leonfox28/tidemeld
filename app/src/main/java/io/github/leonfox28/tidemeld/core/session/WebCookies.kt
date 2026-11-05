package io.github.leonfox28.tidemeld.core.session

import android.webkit.CookieManager
import io.github.leonfox28.tidemeld.core.net.WeiboCookieJar
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * The WebView's cookie store, shared by the login page, the in-app browser and session renewal.
 * Weibo's session cookie (`SUB`) is HttpOnly: page scripts can't see it, but the store can.
 */
interface WebCookies {
    /** The cookies the WebView would send to [url], keyed by name. */
    suspend fun cookies(url: String): Map<String, String>

    /** The WebView's cookies for Weibo's two sites, keyed by site. */
    suspend fun readWeiboCookies(): Map<String, Map<String, String>> =
        mapOf(
            WeiboCookieJar.WEB to cookies("https://weibo.com/"),
            WeiboCookieJar.MOBILE to cookies("https://m.weibo.cn/"),
        )

    /** Deletes every WebView cookie, signing the embedded browser out. */
    suspend fun clearAll()

    /** Signs out only these domains; unrelated platforms remain signed in. */
    suspend fun clearDomains(domains: List<String>)

    /** Installs a verified account's cookies before opening its platform's web page. */
    suspend fun setCookies(host: String, cookies: Map<String, String>)
}

class WebViewCookies : WebCookies {
    override suspend fun setCookies(host: String, cookies: Map<String, String>) =
        withContext(Dispatchers.Main) {
            require(host in setOf("x.com", "weibo.com", "weibo.cn"))
            val manager = CookieManager.getInstance()
            for ((name, value) in cookies) {
                if (
                    !name.matches(Regex("[A-Za-z0-9_-]+")) ||
                        value.any { it == ';' || it == '\r' || it == '\n' }
                )
                    continue
                val httpOnly = if (name in setOf("auth_token", "SUB", "SUBP")) "; HttpOnly" else ""
                suspendCancellableCoroutine { continuation ->
                    manager.setCookie(
                        "https://$host/",
                        "$name=$value; Domain=.$host; Path=/; Secure; SameSite=None$httpOnly",
                    ) {
                        continuation.resume(Unit)
                    }
                }
            }
            manager.flush()
        }

    override suspend fun cookies(url: String): Map<String, String> =
        withContext(Dispatchers.Main) {
            parseCookieHeader(CookieManager.getInstance().getCookie(url))
        }

    override suspend fun clearAll() =
        withContext(Dispatchers.Main) {
            val manager = CookieManager.getInstance()
            suspendCancellableCoroutine { continuation ->
                manager.removeAllCookies { continuation.resume(Unit) }
            }
            manager.flush()
        }

    override suspend fun clearDomains(domains: List<String>) =
        withContext(Dispatchers.Main) {
            val manager = CookieManager.getInstance()
            for (domain in domains) {
                val hosts =
                    listOf(domain, "www.$domain", "m.$domain", "passport.$domain", "login.$domain")
                for (host in hosts) {
                    for (path in listOf("/", "/i/", "/sso/")) {
                        val url = "https://$host$path"
                        for (name in parseCookieHeader(manager.getCookie(url)).keys) {
                            for (cookieDomain in
                                listOf("", "; Domain=$host", "; Domain=.$domain")) {
                                val expired =
                                    "$name=; Max-Age=0; Path=$path$cookieDomain; Secure; HttpOnly"
                                suspendCancellableCoroutine { continuation ->
                                    manager.setCookie(url, expired) { continuation.resume(Unit) }
                                }
                            }
                        }
                    }
                }
            }
            manager.flush()
        }
}

/**
 * The cookies in a `Cookie` header such as CookieManager gives, `a=1; b=2`. Values may contain `=`.
 * When names repeat (one cookie per domain, say), the last one wins.
 */
fun parseCookieHeader(header: String?): Map<String, String> = buildMap {
    for (part in header.orEmpty().split(';')) {
        val pair = part.trim()
        val eq = pair.indexOf('=')
        if (eq > 0) put(pair.substring(0, eq), pair.substring(eq + 1))
    }
}
