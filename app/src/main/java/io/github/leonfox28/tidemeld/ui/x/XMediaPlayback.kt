package io.github.leonfox28.tidemeld.ui.x

import io.github.leonfox28.tidemeld.AppGraph
import io.github.leonfox28.tidemeld.core.media.*
import io.github.leonfox28.tidemeld.core.net.*
import io.github.leonfox28.tidemeld.data.model.*

fun xVideoRequest(
    graph: AppGraph,
    owner: String,
    postId: String,
    index: Int,
    known: VideoInfo,
): VideoRequest {
    val revision = graph.accounts.find(owner)?.revision
    return VideoRequest(
        known.coverUrl,
        mapOf("Referer" to "https://x.com/", "User-Agent" to BROWSER_USER_AGENT),
    ) { refresh ->
        fun checkAccount() {
            val account = graph.accounts.find(owner)
            if (account == null || account.revision != revision || account.expired)
                throw SessionExpiredException()
        }
        checkAccount()
        val existing = if (refresh) null else freshStreamUrl(known)
        if (existing != null) VideoSource(existing, fetched = false)
        else {
            val page = graph.xInteractions.conversation(owner, postId, null)
            checkAccount()
            val url =
                page.post
                    ?.media
                    ?.filterIsInstance<MixedMedia.Video>()
                    ?.getOrNull(index)
                    ?.video
                    ?.streamUrls
                    ?.firstOrNull() ?: throw WeiboApiException("这条帖子的视频暂时无法播放")
            VideoSource(url, fetched = true)
        }
    }
}
