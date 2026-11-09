package io.github.leonfox28.tidemeld.ui.status

import io.github.leonfox28.tidemeld.core.media.*
import io.github.leonfox28.tidemeld.data.api.WeiboApi
import io.github.leonfox28.tidemeld.data.model.Status
import io.github.leonfox28.tidemeld.data.model.WeiboVideoLink

fun weiboVideoRequest(api: WeiboApi, status: Status, index: Int?) =
    VideoRequest(status.videoAt(index)?.coverUrl, VideoHttpHeaders) { refresh ->
        resolveVideoUrl(api, status.id, index, status.videoAt(index), refresh)
    }

fun weiboVideoRequest(api: WeiboApi, link: WeiboVideoLink) =
    VideoRequest(null, VideoHttpHeaders) { _ ->
        VideoSource(api.fetchLinkedVideo(link).streamUrls.first(), fetched = true)
    }

fun weiboPhotoMotion(api: WeiboApi, statusId: String?) =
    PhotoMotion(VideoHttpHeaders, canRefresh = statusId != null) { pic, refresh ->
        resolveLivePhotoUrl(api, pic, statusId, refresh)
    }
