package io.github.leonfox28.tidemeld.data.x

import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class XPostTest {
    private fun tweet(id: String, quote: JsonObject? = null): JsonObject = buildJsonObject {
        put("rest_id", id)
        put(
            "core",
            Json.parseToJsonElement(
                """{"user_results":{"result":{"core":{"name":"示例作者","screen_name":"fixture"},"avatar":{"image_url":"https://example.com/avatar.jpg"}}}}"""
            ),
        )
        put(
            "legacy",
            Json.parseToJsonElement(
                """{"full_text":"A &amp; B https://t.co/synthetic","created_at":"Thu Nov 05 08:00:00 +0000 2026","entities":{"urls":[{"url":"https://t.co/synthetic","expanded_url":"https://example.com/article"}]},"extended_entities":{"media":[{"type":"photo","media_url_https":"https://example.com/photo.jpg"},{"type":"video","media_url_https":"https://example.com/video.jpg","video_info":{"variants":[{"content_type":"video/mp4","bitrate":1,"url":"https://example.com/low.mp4"},{"content_type":"video/mp4","bitrate":2,"url":"https://example.com/high.mp4"}]}}]}}"""
            ),
        )
        quote?.let { put("quoted_status_result", buildJsonObject { put("result", it) }) }
    }

    @Test
    fun `timeline handles visibility wrappers modules ads and cursor without promoting quoted posts`() {
        val item = buildJsonObject {
            put(
                "itemContent",
                buildJsonObject {
                    put(
                        "tweet_results",
                        buildJsonObject {
                            put("result", buildJsonObject { put("tweet", tweet("1", tweet("2"))) })
                        },
                    )
                    put("promotedMetadata", buildJsonObject {})
                },
            )
        }
        val json = buildJsonObject {
            put(
                "data",
                buildJsonObject {
                    put(
                        "home",
                        buildJsonObject {
                            put(
                                "home_timeline_urt",
                                buildJsonObject {
                                    put(
                                        "instructions",
                                        buildJsonArray {
                                            add(
                                                buildJsonObject {
                                                    put(
                                                        "entries",
                                                        buildJsonArray {
                                                            add(
                                                                buildJsonObject {
                                                                    put("content", item)
                                                                }
                                                            )
                                                            add(
                                                                Json.parseToJsonElement(
                                                                    """{"content":{"cursorType":"Bottom","value":"next"}}"""
                                                                )
                                                            )
                                                        },
                                                    )
                                                }
                                            )
                                        },
                                    )
                                },
                            )
                        },
                    )
                },
            )
        }
        val page = parseXTimeline(json)
        assertEquals(listOf("1"), page.items.map { it.id })
        val post = page.items.single()
        assertTrue(post.promoted)
        assertEquals("2", post.quote?.id)
        assertEquals("A & B https://example.com/article", post.text)
        assertEquals(1, post.pictures.size)
        assertEquals("https://example.com/high.mp4", post.videoUrl)
        assertEquals("next", page.nextCursor)
        assertNull(parseXTimeline(json, "next").nextCursor)
    }

    @Test(expected = WeiboApiException::class)
    fun `unknown timeline shape is an error rather than an empty feed`() {
        parseXTimeline(buildJsonObject {})
    }
}
