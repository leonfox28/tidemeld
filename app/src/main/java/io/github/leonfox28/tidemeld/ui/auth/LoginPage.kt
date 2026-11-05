package io.github.leonfox28.tidemeld.ui.auth

import android.annotation.SuppressLint
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.github.leonfox28.tidemeld.AppGraph
import io.github.leonfox28.tidemeld.LocalAppGraph
import io.github.leonfox28.tidemeld.core.accounts.SocialPlatform
import io.github.leonfox28.tidemeld.core.net.BROWSER_USER_AGENT
import io.github.leonfox28.tidemeld.core.net.SessionExpiredException
import io.github.leonfox28.tidemeld.core.net.WeiboCookieJar
import io.github.leonfox28.tidemeld.core.net.WeiboException
import io.github.leonfox28.tidemeld.core.util.devLog
import io.github.leonfox28.tidemeld.ui.navigation.LocalNavigator
import io.github.leonfox28.tidemeld.ui.navigation.Navigator
import io.github.leonfox28.tidemeld.ui.navigation.Route
import io.github.leonfox28.tidemeld.ui.settings.REPO_URL
import io.github.leonfox28.tidemeld.ui.widget.AppSnackbarHost
import io.github.leonfox28.tidemeld.ui.widget.CloseButton
import io.github.leonfox28.tidemeld.ui.widget.LocalSnackbars
import io.github.leonfox28.tidemeld.ui.widget.openExternally
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Weibo's own sign-in page; after signing in it returns to weibo.com. */
const val LOGIN_URL =
    "https://passport.weibo.com/sso/signin?entry=miniblog&source=miniblog&url=https%3A%2F%2Fweibo.com%2F"

/**
 * Hosts Weibo's official login page in a WebView. The password is typed into Weibo's page and never
 * passes through tidemeld.
 *
 * After every main-frame load the WebView's cookies are checked against the API, wherever the page
 * landed: passport sets the weibo.com cookies before its cross-domain hop through
 * login.sina.com.cn, and that hop can fail (HTTP 403 inside a WebView) without affecting the
 * weibo.com session.
 *
 * Closes once signed in, saying so.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginPage(platform: SocialPlatform = SocialPlatform.Weibo) {
    val graph = LocalAppGraph.current
    val context = LocalContext.current
    val navigator = LocalNavigator.current
    val snackbars = LocalSnackbars.current
    val scope = rememberCoroutineScope()
    val login = remember(platform) { LoginCheck(graph, navigator, snackbars, scope, platform) }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var prepared by remember(platform) { mutableStateOf(false) }
    LaunchedEffect(platform) {
        graph.webCookies.clearDomains(platform.domains)
        prepared = true
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("登录${platform.label}") },
                navigationIcon = { CloseButton() },
                actions = {
                    TextButton(onClick = login::check) { Text("完成登录") }
                    IconButton(onClick = { webView?.reload() }) {
                        Icon(Icons.Filled.Refresh, contentDescription = "刷新")
                    }
                },
            )
        },
        snackbarHost = { AppSnackbarHost() },
    ) { padding ->
        Column(Modifier.padding(padding).consumeWindowInsets(padding).imePadding()) {
            Text(
                "下方是${platform.label}官方登录页面。登录信息直接提交给${platform.label}，登录状态仅保存在本机。",
                modifier =
                    Modifier.fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                style = MaterialTheme.typography.bodySmall,
            )
            TextButton(
                onClick = {
                    context.openExternally("$REPO_URL/blob/main/docs/PRIVACY.md", snackbars, scope)
                },
                modifier = Modifier.align(Alignment.CenterHorizontally),
            ) {
                Text("隐私政策")
            }
            if (login.progress < 100) {
                LinearProgressIndicator(
                    progress = { login.progress / 100f },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Box(Modifier.weight(1f)) {
                if (prepared)
                    AndroidView(
                        factory = { context ->
                            loginWebView(context, login).also {
                                webView = it
                                it.loadUrl(
                                    if (platform == SocialPlatform.Weibo) LOGIN_URL
                                    else "https://x.com/i/flow/login"
                                )
                            }
                        },
                        modifier = Modifier.fillMaxSize(),
                        onRelease = WebView::destroy,
                    )
                if (login.verifying) {
                    Box(
                        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.26f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
            }
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
private fun loginWebView(context: android.content.Context, login: LoginCheck) =
    WebView(context).apply {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.userAgentString = BROWSER_USER_AGENT
        webViewClient =
            object : WebViewClient() {
                // Only web pages: block app links such as sinaweibo://.
                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest,
                ): Boolean = request.url.scheme != "https" && request.url.scheme != "http"

                override fun onPageFinished(view: WebView, url: String?) {
                    login.check()
                }

                override fun onReceivedError(
                    view: WebView,
                    request: WebResourceRequest,
                    error: WebResourceError,
                ) {
                    if (request.isForMainFrame) login.check()
                }
            }
        webChromeClient =
            object : WebChromeClient() {
                override fun onProgressChanged(view: WebView, newProgress: Int) {
                    login.progress = newProgress
                }
            }
    }

/** Checks the WebView's cookies after each page, and signs in with them once they're a user's. */
private class LoginCheck(
    private val graph: AppGraph,
    private val navigator: Navigator,
    private val snackbars: SnackbarHostState,
    private val scope: CoroutineScope,
    private val platform: SocialPlatform,
) {
    var progress by mutableIntStateOf(0)
    var verifying by mutableStateOf(false)
        private set

    /** A SUB the API identified as a visitor's; not checked again until the WebView has another. */
    private var visitorSub: String? = null

    fun check() {
        if (verifying) return
        scope.launch {
            if (platform == SocialPlatform.X) {
                verifying = true
                try {
                    val cookies = graph.webCookies.cookies("https://x.com/")
                    if (cookies["auth_token"].isNullOrBlank() || cookies["ct0"].isNullOrBlank())
                        return@launch
                    val api = graph.xApi ?: return@launch
                    val verified = api.verify(cookies)
                    graph.accounts.add(platform, verified)
                    navigator.pop()
                    if (navigator.backStack.lastOrNull() == Route.Login) navigator.pop()
                    graph.appScope.launch { snackbars.showSnackbar("X 登录成功") }
                } catch (e: WeiboException) {
                    launch { snackbars.showSnackbar(e.message) }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (_: Exception) {
                    launch { snackbars.showSnackbar("账号保存失败，请重试") }
                } finally {
                    verifying = false
                }
                return@launch
            }
            val cookies = graph.webCookies.readWeiboCookies()
            val sub = cookies[WeiboCookieJar.WEB]?.get("SUB")
            devLog(
                "login check: weibo.com=${cookies[WeiboCookieJar.WEB]?.keys?.toList()} " +
                    "weibo.cn=${cookies[WeiboCookieJar.MOBILE]?.keys?.toList()}"
            )
            if (sub == null || sub == visitorSub || verifying) return@launch
            verifying = true
            try {
                graph.accounts.add(platform, graph.session.verifyLogin(cookies))
                navigator.pop()
                if (navigator.backStack.lastOrNull() == Route.Login) navigator.pop()
                // The page is gone by the time this shows.
                graph.appScope.launch { snackbars.showSnackbar("登录成功") }
            } catch (_: SessionExpiredException) {
                // Visitor cookies only: the user hasn't signed in yet.
                devLog("login check: not signed in yet")
                visitorSub = sub
            } catch (e: WeiboException) {
                launch { snackbars.showSnackbar(e.message) }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (_: Exception) {
                launch { snackbars.showSnackbar("账号保存失败，请重试") }
            } finally {
                verifying = false
            }
        }
    }
}
