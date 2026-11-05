package io.github.leonfox28.maxbo.data.api

import io.github.leonfox28.maxbo.core.net.RequestThrottle
import io.github.leonfox28.maxbo.core.net.WeiboApiException
import io.github.leonfox28.maxbo.core.net.WeiboCookieJar
import io.github.leonfox28.maxbo.core.net.WeiboHttp
import io.github.leonfox28.maxbo.data.model.PicType
import io.github.leonfox28.maxbo.support.FakeWeibo
import io.github.leonfox28.maxbo.support.json
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

val guestFeedJson =
    """{"ok":1,"data":{"cardlistInfo":{"since_id":8},"cards":[
 {"card_type":9,"mblog":{"id":"11","bid":"Ab11","user":{"id":1,"screen_name":"示例作者"},"text":"公开图片示例","pics":[{"pid":"picture","url":"https://example.com/small.gif","large":{"url":"https://example.com/large.gif","geo":{"width":1200,"height":800}}}]}},
 {"card_type":11,"card_group":[{"card_type":9,"is_ad":1,"mblog":{"id":"12","text":"推广内容示例","page_info":{"type":"video","object_type":11,"page_pic":{"url":"https://example.com/cover.jpg","width":"640","height":"360"},"media_info":{"duration":30,"stream_url":"https://example.com/low.mp4"},"urls":{"mp4_720p_mp4":"http://example.com/high.mp4"}}}}]}
 ]}}"""

@RunWith(RobolectricTestRunner::class)
class GuestWeiboApiTest {
    private val web = FakeWeibo()
    private val jar = WeiboCookieJar()
    private var preparations = 0
    private val api =
        GuestWeiboApi(WeiboHttp.create(web.client, jar, RequestThrottle(minIntervalMs = 0)), jar) {
            preparations++
            mapOf(
                WeiboCookieJar.MOBILE to mapOf("SUB" to "visitor"),
                WeiboCookieJar.WEB to mapOf("SUB" to "must-not-use"),
            )
        }

    @After fun tearDown() = web.close()

    @Test
    fun `visitor feed preserves cards and ads and decodes mobile media without paging`() = runTest {
        web.respond = {
            json(
                if (it.url.encodedPath == "/api/config") """{"ok":1,"data":{"login":false}}"""
                else guestFeedJson
            )
        }
        val page = api.fetchTimeline()
        assertEquals(listOf("11", "12"), page.items.map { it.id })
        assertNull(page.nextCursor)
        assertEquals("Ab11", page.items[0].mblogId)
        assertEquals(PicType.Gif, page.items[0].pics.single().type)
        assertEquals(1200, page.items[0].pics.single().largest!!.width)
        assertTrue(page.items[1].isAd)
        assertEquals(
            listOf("https://example.com/high.mp4", "https://example.com/low.mp4"),
            page.items[1].video!!.streamUrls,
        )
        assertEquals(640f / 360f, page.items[1].video!!.aspectRatio!!, 0.001f)
        assertEquals(2, web.requests.size)
        assertTrue(
            web.requests.all {
                it.url.host == "m.weibo.cn" && it.headers["Cookie"] == "SUB=visitor"
            }
        )
        assertNull(jar.value(WeiboCookieJar.WEB, "SUB"))
        api.fetchTimeline()
        assertEquals(1, preparations)
        assertEquals(3, web.requests.size)
        assertTrue(
            web.requests.none {
                it.url.queryParameter("page") != null || it.url.queryParameter("since_id") != null
            }
        )
    }

    @Test
    fun `an account cookie cannot be accepted as a visitor session`() = runTest {
        web.respond = { json("""{"ok":1,"data":{"login":true}}""") }
        try {
            api.fetchTimeline()
            fail("must reject a signed-in web session")
        } catch (_: WeiboApiException) {}
        assertEquals(listOf("/api/config"), web.requests.map { it.url.encodedPath })
        assertTrue(jar.isEmpty)
    }

    @Test
    fun `a guest limit makes no automatic retry and the next manual refresh prepares again`() =
        runTest {
            web.respond = {
                json(
                    if (it.url.encodedPath == "/api/config") """{"ok":1,"data":{"login":false}}"""
                    else """{"ok":-100}"""
                )
            }
            repeat(2) {
                try {
                    api.fetchTimeline()
                    fail("must show the guest restriction")
                } catch (e: WeiboApiException) {
                    assertTrue(e.message!!.contains("游客"))
                }
            }
            assertEquals(2, preparations)
            assertEquals(4, web.requests.size)
            assertTrue(jar.isEmpty)
        }
}
