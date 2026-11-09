package io.github.leonfox28.tidemeld

import android.content.Context
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.preferencesDataStoreFile
import coil3.ImageLoader
import io.github.leonfox28.tidemeld.core.accounts.*
import io.github.leonfox28.tidemeld.core.media.ImageDiskCache
import io.github.leonfox28.tidemeld.core.media.PictureCache
import io.github.leonfox28.tidemeld.core.media.WeiboPictureCache
import io.github.leonfox28.tidemeld.core.media.weiboImageLoader
import io.github.leonfox28.tidemeld.core.net.RequestThrottle
import io.github.leonfox28.tidemeld.core.net.WeiboCookieJar
import io.github.leonfox28.tidemeld.core.net.WeiboHttp
import io.github.leonfox28.tidemeld.core.session.EncryptedFileSessionStorage
import io.github.leonfox28.tidemeld.core.session.KeystoreSessionCipher
import io.github.leonfox28.tidemeld.core.session.SessionController
import io.github.leonfox28.tidemeld.core.session.WebCookies
import io.github.leonfox28.tidemeld.core.session.WebGuestSession
import io.github.leonfox28.tidemeld.core.session.WebViewCookies
import io.github.leonfox28.tidemeld.core.session.WebViewSessionRenewer
import io.github.leonfox28.tidemeld.core.settings.DataStoreSettingsStorage
import io.github.leonfox28.tidemeld.core.settings.SettingsController
import io.github.leonfox28.tidemeld.data.api.GuestWeiboApi
import io.github.leonfox28.tidemeld.data.api.WeiboApi
import io.github.leonfox28.tidemeld.data.x.XWebApi
import io.github.leonfox28.tidemeld.ui.compose.ComposeDraftController
import io.github.leonfox28.tidemeld.ui.compose.ContentPictureReader
import io.github.leonfox28.tidemeld.ui.compose.PictureReader
import io.github.leonfox28.tidemeld.ui.interactions.LikesController
import io.github.leonfox28.tidemeld.ui.interactions.OpenLists
import io.github.leonfox28.tidemeld.ui.interactions.RepostDrafts
import io.github.leonfox28.tidemeld.ui.notifications.UnreadNoticesController
import io.github.leonfox28.tidemeld.ui.timeline.GuestTimelineController
import io.github.leonfox28.tidemeld.ui.timeline.SocialFeedController
import io.github.leonfox28.tidemeld.ui.timeline.TimelineController
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath

/**
 * The app's long-lived objects, made by hand: what Riverpod's providers were in the Flutter app.
 * Tests build one from fakes.
 */
class AppGraph(
    /** For work that outlives any page, such as saving a setting. */
    val appScope: CoroutineScope,
    val settings: SettingsController,
    val session: SessionController,
    /** Signed in as [session] says, renewing the session when Weibo rejects it. */
    val api: WeiboApi,
    val webCookies: WebCookies,
    val timeline: TimelineController,
    val unread: UnreadNoticesController,
    /** Reads the pictures the user picks, to upload them. */
    val pictures: PictureReader,
    /** The pictures kept on the device, for the settings page. */
    val pictureCache: PictureCache,
    imageLoader: () -> ImageLoader,
    guestApi: GuestWeiboApi? = null,
    accountStorage: AccountStorage = MemoryAccountStorage(),
    restoredAccounts: List<SocialAccount> = emptyList(),
    val xApi: XWebApi? = null,
    sharedAccounts: AccountManager? = null,
    val profileRelationships: io.github.leonfox28.tidemeld.ui.social.ProfileRelationships =
        io.github.leonfox28.tidemeld.ui.social.ProfileRelationships(),
    onPostChanged: ((io.github.leonfox28.tidemeld.data.model.Status, Boolean) -> Unit)? = null,
) {
    val accounts =
        sharedAccounts
            ?: AccountManager(restoredAccounts, accountStorage, session, webCookies, appScope)
    private val accountGraphs = mutableMapOf<String, Pair<Long, AppGraph>>()

    fun forAccount(key: String): AppGraph? {
        val account =
            accounts.find(key)?.takeIf { it.platform == SocialPlatform.Weibo && !it.expired }
                ?: return null
        accountGraphs[key]
            ?.takeIf { it.first == account.revision }
            ?.let {
                if (it.second.session.jar.toMap() != account.session.cookies)
                    it.second.session.jar.replaceAll(account.session.cookies)
                return it.second
            }
        val scopedStorage =
            object : io.github.leonfox28.tidemeld.core.session.SessionStorage {
                override suspend fun load() = accounts.find(key)?.session

                override suspend fun save(
                    session: io.github.leonfox28.tidemeld.core.session.StoredSession
                ) {
                    if (accounts.find(key)?.revision == account.revision)
                        accounts.updateCookies(key, session.cookies)
                }

                override suspend fun clear() {
                    if (accounts.find(key)?.revision == account.revision) accounts.expire(key)
                }
            }
        val scopedSession = session.isolated(account.session, scopedStorage)
        val scopedApi = scopedSession.apiForSession()
        val scoped =
            AppGraph(
                appScope,
                settings,
                scopedSession,
                scopedApi,
                webCookies,
                TimelineController(scopedApi, scopedSession, appScope),
                UnreadNoticesController(scopedApi, scopedSession, appScope),
                pictures,
                pictureCache,
                { imageLoader },
                xApi = xApi,
                sharedAccounts = accounts,
                profileRelationships = profileRelationships,
                onPostChanged = { post, added -> socialFeed.ownPostChanged(key, post, added) },
            )
        accountGraphs[key] = account.revision to scoped
        return scoped
    }

    val xInteractions by lazy {
        io.github.leonfox28.tidemeld.ui.x.XInteractions(accounts, xApi, profileRelationships)
    }

    val socialFeed by lazy {
        SocialFeedController(accounts, appScope) { account, cursor ->
            when (account.platform) {
                SocialPlatform.Weibo -> {
                    val service =
                        forAccount(account.key)?.api
                            ?: throw io.github.leonfox28.tidemeld.core.net.SessionExpiredException()
                    service.fetchHomeTimeline(account.session.account.uid, cursor).let { page ->
                        io.github.leonfox28.tidemeld.data.model.Paged(
                            page.statuses.map {
                                io.github.leonfox28.tidemeld.ui.timeline.FeedPost.Weibo(
                                    account.key,
                                    it,
                                )
                            },
                            page.nextCursor,
                        )
                    }
                }
                SocialPlatform.X -> {
                    val service =
                        xApi
                            ?: throw io.github.leonfox28.tidemeld.core.net.WeiboApiException(
                                "X 接口配置不可用"
                            )
                    val started = xInteractions.readStamp
                    service
                        .timeline(account.session, cursor) { cookies ->
                            if (accounts.find(account.key)?.revision == account.revision)
                                accounts.updateCookies(account.key, cookies)
                        }
                        .let { page ->
                            xInteractions.ingest(account, page.items, started)
                            io.github.leonfox28.tidemeld.data.model.Paged(
                                page.items.map {
                                    io.github.leonfox28.tidemeld.ui.timeline.FeedPost.X(
                                        account.key,
                                        it,
                                    )
                                },
                                page.nextCursor,
                            )
                        }
                }
            }
        }
    }
    val guestTimeline = GuestTimelineController(guestApi, session, appScope)
    /** Loads Weibo's pictures; made on first use. */
    val imageLoader: ImageLoader by lazy(imageLoader)

    val openLists =
        OpenLists(timeline) { post, added ->
            if (onPostChanged != null) onPostChanged(post, added)
            else
                socialFeed.ownPostChanged(
                    "weibo:${(session.state.value as? io.github.leonfox28.tidemeld.core.session.SessionState.SignedIn)?.account?.uid}",
                    post,
                    added,
                )
        }
    val likes = LikesController(api, session, appScope)
    val composeDraft = ComposeDraftController(api, pictures, openLists, session, appScope)
    val repostDrafts = RepostDrafts(session, appScope)

    companion object {
        /** The real thing, reading the saved settings and session before the first frame. */
        fun create(context: Context): AppGraph {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val settingsStorage =
                DataStoreSettingsStorage(
                    PreferenceDataStoreFactory.create {
                        context.preferencesDataStoreFile("settings")
                    }
                )
            // Never backed up, whatever the backup rules say.
            val sessionStorage =
                EncryptedFileSessionStorage(
                    File(context.noBackupFilesDir, "session"),
                    KeystoreSessionCipher(),
                )
            // Before the first frame, so a chosen theme doesn't flash the
            // default, and a signed-in user doesn't see the login prompt.
            val (initialSettings, restored) =
                runBlocking(Dispatchers.IO) { settingsStorage.load() to sessionStorage.load() }
            val accountStorage =
                EncryptedAccountStorage(
                    File(context.noBackupFilesDir, "accounts"),
                    KeystoreSessionCipher(),
                )
            val restoredAccounts = runBlocking(Dispatchers.IO) { accountStorage.load() }

            val throttle = RequestThrottle()
            val base = OkHttpClient()
            val httpFor = { jar: WeiboCookieJar -> WeiboHttp.create(base, jar, throttle) }
            val webCookies = WebViewCookies()
            val session =
                SessionController(
                    restored = restored,
                    storage = sessionStorage,
                    webCookies = webCookies,
                    renewer = WebViewSessionRenewer(context.applicationContext, webCookies),
                    httpFor = httpFor,
                    scope = scope,
                )
            val api = WeiboApi(httpFor(session.jar), onSessionExpired = session::renewOrExpire)
            val guestJar = WeiboCookieJar()
            val guestApi =
                GuestWeiboApi(
                    httpFor(guestJar),
                    guestJar,
                    WebGuestSession(context.applicationContext, webCookies)::prepare,
                )
            val diskCache =
                ImageDiskCache(
                    context.cacheDir.resolve("image_cache").toOkioPath(),
                    initialSettings.imageCacheLimitMb * MB,
                )
            val imageLoader by lazy {
                weiboImageLoader(context.applicationContext, base, diskCache)
            }
            return AppGraph(
                appScope = scope,
                settings = SettingsController(initialSettings, settingsStorage, scope),
                session = session,
                api = api,
                webCookies = webCookies,
                timeline = TimelineController(api, session, scope),
                unread = UnreadNoticesController(api, session, scope),
                pictures = ContentPictureReader(context.applicationContext),
                pictureCache = WeiboPictureCache(diskCache) { imageLoader },
                imageLoader = { imageLoader },
                guestApi = guestApi,
                accountStorage = accountStorage,
                restoredAccounts = restoredAccounts,
                xApi =
                    XWebApi(
                        base,
                        Json.parseToJsonElement(
                                context.assets.open("x-web.json").bufferedReader().use {
                                    it.readText()
                                }
                            )
                            .jsonObject,
                        throttle,
                    ),
            )
        }
    }
}

val LocalAppGraph = staticCompositionLocalOf<AppGraph> { error("No AppGraph provided") }

/** Bytes in a megabyte, as the settings count them. */
const val MB = 1024L * 1024
