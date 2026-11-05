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
    fun `timeline handles visibility wrappers and cursor without flattening quoted posts`() {
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
        assertFalse(post.promoted)
        assertEquals("2", post.quote?.id)
        assertEquals("A & B https://example.com/article", post.text)
        assertEquals(1, post.pictures.size)
        assertEquals("https://example.com/high.mp4", post.videoUrl)
        assertEquals("next", page.nextCursor)
        assertNull(parseXTimeline(json, "next").nextCursor)
    }

    @Test
    fun `conversation excludes ancestors and ads retains replies and reads metrics from original repost`() {
        fun entry(id: String, parent: String? = null, ad: Boolean = false): JsonObject {
            val base = tweet(id).toMutableMap()
            base["legacy"] =
                JsonObject(
                    base["legacy"]!!.jsonObject +
                        buildJsonObject {
                            parent?.let { put("in_reply_to_status_id_str", it) }
                            put("favorite_count", 12)
                            put("retweet_count", 2)
                            put("reply_count", 3)
                            put("favorited", true)
                            put("retweeted", true)
                        }
                )
            return buildJsonObject {
                put(
                    "content",
                    buildJsonObject {
                        put(
                            "itemContent",
                            buildJsonObject {
                                put(
                                    "tweet_results",
                                    buildJsonObject { put("result", JsonObject(base)) },
                                )
                                if (ad) put("promotedMetadata", buildJsonObject {})
                            },
                        )
                    },
                )
            }
        }
        val entries = buildJsonArray {
            add(entry("ancestor"))
            add(entry("42", "ancestor"))
            add(entry("nested", "reply"))
            add(entry("reply", "42"))
            add(entry("ad", ad = true))
            add(entry("promoted-reply", "42", ad = true))
            add(Json.parseToJsonElement("""{"content":{"cursorType":"Bottom","value":"next"}}"""))
        }
        val json = buildJsonObject {
            put(
                "data",
                buildJsonObject {
                    put(
                        "threaded_conversation_with_injections_v2",
                        buildJsonObject {
                            put(
                                "instructions",
                                buildJsonArray { add(buildJsonObject { put("entries", entries) }) },
                            )
                        },
                    )
                },
            )
        }
        val conversation = parseXConversation(json, "42")
        assertEquals(listOf("nested", "reply"), conversation.replies.items.map { it.id })
        assertEquals(XMetrics(12, 2, 3, true, true), conversation.post!!.metrics)
        assertEquals("next", conversation.replies.nextCursor)
        assertNull(parseXConversation(json, "42", "next").replies.nextCursor)
        val original =
            entries[1]
                .jsonObject["content"]!!
                .jsonObject["itemContent"]!!
                .jsonObject["tweet_results"]!!
                .jsonObject["result"]!!
        val repost =
            JsonObject(
                tweet("wrapper") +
                    ("legacy" to
                        buildJsonObject {
                            put(
                                "retweeted_status_result",
                                buildJsonObject { put("result", original) },
                            )
                        })
            )
        val parsed = parseXPost(repost)!!
        assertEquals("wrapper", parsed.id)
        assertEquals("42", parsed.originalId)
        assertTrue(parsed.metrics.liked)
    }

    @Test
    fun `timeline filters promoted placements and modules before deduplication and preserves empty page cursor`() {
        fun item(id: String, promoted: Boolean, repost: Boolean = false): JsonObject =
            buildJsonObject {
                val post =
                    if (repost)
                        JsonObject(
                            tweet(id) +
                                ("legacy" to
                                    buildJsonObject {
                                        put(
                                            "retweeted_status_result",
                                            buildJsonObject { put("result", tweet("original")) },
                                        )
                                    })
                        )
                    else tweet(id, tweet("quoted"))
                put("tweet_results", buildJsonObject { put("result", post) })
                if (promoted) put("promotedMetadata", buildJsonObject {})
            }
        fun entry(item: JsonObject) = buildJsonObject {
            put("content", buildJsonObject { put("itemContent", item) })
        }
        fun module(vararg items: JsonObject) = buildJsonObject {
            put(
                "content",
                buildJsonObject {
                    put(
                        "items",
                        buildJsonArray {
                            items.forEach {
                                add(
                                    buildJsonObject {
                                        put("item", buildJsonObject { put("itemContent", it) })
                                    }
                                )
                            }
                        },
                    )
                },
            )
        }
        fun timeline(vararg entries: JsonObject) =
            Json.parseToJsonElement(
                    """{"data":{"home":{"home_timeline_urt":{"instructions":[
                {"entries":${JsonArray(entries.toList())}},
                {"entry":{"content":{"cursorType":"Bottom","value":"next"}}}
            ]}}}}"""
                )
                .jsonObject
        val ad = entry(item("1", true))
        val adModule = module(item("ad-repost", true, repost = true))
        val page =
            parseXTimeline(
                timeline(
                    ad,
                    adModule,
                    entry(item("1", false)),
                    module(item("module-ad", true), item("module-organic", false)),
                )
            )
        assertEquals(listOf("1", "module-organic"), page.items.map { it.id })
        assertTrue(page.items.none { it.promoted })
        assertEquals("next", page.nextCursor)
        val onlyAds = timeline(ad, adModule)
        assertTrue(parseXTimeline(onlyAds).items.isEmpty())
        assertEquals("next", parseXTimeline(onlyAds).nextCursor)
        assertNull(parseXTimeline(onlyAds, "next").nextCursor)
    }

    @Test(expected = WeiboApiException::class)
    fun `unknown timeline shape is an error rather than an empty feed`() {
        parseXTimeline(buildJsonObject {})
    }
}
