package io.github.leonfox28.tidemeld.data.model

import okhttp3.HttpUrl

/** A video object linked from text, which need not belong to the enclosing post. */
data class WeiboVideoLink(val objectId: String) {
    companion object {
        fun from(url: HttpUrl): WeiboVideoLink? {
            val path = url.pathSegments.joinToString("/", prefix = "/")
            val objectId =
                when (url.host) {
                    "h5.video.weibo.com",
                    "video.weibo.com" ->
                        when {
                            path.startsWith("/show/") -> path.removePrefix("/show/")
                            path == "/show" -> url.queryParameter("fid")
                            else -> null
                        }
                    "weibo.com",
                    "www.weibo.com" ->
                        when {
                            path.startsWith("/tv/show/") -> path.removePrefix("/tv/show/")
                            path.startsWith("/tv/v/") -> url.queryParameter("fid")
                            else -> null
                        }
                    else -> null
                } ?: return null
            return objectId.takeIf { it.matches(Regex("[0-9]+:[0-9]+")) }?.let(::WeiboVideoLink)
        }
    }
}
