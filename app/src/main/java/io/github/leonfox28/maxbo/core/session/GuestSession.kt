package io.github.leonfox28.maxbo.core.session

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.github.leonfox28.maxbo.core.net.BROWSER_USER_AGENT
import io.github.leonfox28.maxbo.core.net.WeiboApiException
import io.github.leonfox28.maxbo.core.net.WeiboCookieJar
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Runs only Weibo's normal visitor setup. It never completes a login or a challenge. */
class WebGuestSession(private val context: Context, private val cookies: WebCookies) {
    @SuppressLint("SetJavaScriptEnabled")
    suspend fun prepare(): Map<String, Map<String, String>> =
        withContext(Dispatchers.Main) {
            // Revisit the official page when a visitor session expires. The caller
            // verifies login:false before using its cookies for any feed request.
            val finished = CompletableDeferred<Unit>()
            val view = WebView(context)
            view.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                userAgentString = BROWSER_USER_AGENT
            }
            view.webViewClient =
                object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        view: WebView,
                        request: WebResourceRequest,
                    ): Boolean = request.url.scheme != "https" && request.url.scheme != "http"

                    override fun onPageFinished(view: WebView, url: String?) {
                        if (android.net.Uri.parse(url.orEmpty()).host == "m.weibo.cn")
                            finished.complete(Unit)
                    }

                    override fun onReceivedError(
                        view: WebView,
                        request: WebResourceRequest,
                        error: WebResourceError,
                    ) {
                        if (request.isForMainFrame) finished.complete(Unit)
                    }
                }
            try {
                view.loadUrl(HOME)
                if (
                    withTimeoutOrNull(30_000) {
                        finished.await()
                        true
                    } != true
                ) {
                    throw WeiboApiException("暂时无法建立游客会话，请稍后重试或登录微博")
                }
                val visitor = cookies.cookies(HOME)
                if (visitor["SUB"] == null) throw WeiboApiException("暂时无法建立游客会话，请稍后重试或登录微博")
                mapOf(WeiboCookieJar.MOBILE to visitor)
            } finally {
                view.stopLoading()
                view.loadUrl("about:blank")
                view.destroy()
            }
        }

    private companion object {
        const val HOME = "https://m.weibo.cn/"
    }
}
