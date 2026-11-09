package io.github.leonfox28.tidemeld.core.media

import io.github.leonfox28.tidemeld.core.net.WeiboApiException
import io.github.leonfox28.tidemeld.data.model.WeiboVideoLink
import io.github.leonfox28.tidemeld.support.FakeWeibo
import io.github.leonfox28.tidemeld.support.form
import io.github.leonfox28.tidemeld.support.json
import io.github.leonfox28.tidemeld.ui.status.weiboVideoRequest
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WeiboVideoLinkTest {
    private val web = FakeWeibo()
    private val link = WeiboVideoLink("1034:5000000000000001")
    private val response =
        """
        {"code":"100000","data":{"Component_Play_Playinfo":{
          "oid":"1034:5000000000000001","object_type":"video","duration_time":61.5,
          "cover_image":"https://wx1.sinaimg.cn/cover.jpg",
          "urls":{"标清 480P":"https://media.test/480.mp4","高清 720P":"http://media.test/720.mp4?Expires=2100000000&ssig=a%2Bb"},
          "stream_url":"https://media.test/fallback.mp4"}}}
        """
            .trimIndent()

    @After fun tearDown() = web.close()

    @Test
    fun `shared player resolves on demand with the source account and refreshes the same object`() =
        runTest {
            web.respond = { json(response) }
            val api = web.api(mapOf("weibo.com" to mapOf("SUB" to "synthetic-8")))
            val request = weiboVideoRequest(api, link)
            assertTrue(web.requests.isEmpty())
            assertEquals("https://weibo.com/", request.headers["Referer"])
            val source = request.resolve(false)
            assertEquals(
                VideoSource(
                    "https://media.test/720.mp4?Expires=2100000000&ssig=a%2Bb",
                    fetched = true,
                ),
                source,
            )
            val sent = web.requests.single()
            assertEquals("POST", sent.method)
            assertEquals("h5.video.weibo.com", sent.url.host)
            assertEquals("/api/component", sent.url.encodedPath)
            assertEquals("/show/${link.objectId}", sent.url.queryParameter("page"))
            assertEquals("SUB=synthetic-8", sent.headers["Cookie"])
            assertEquals(
                Json.parseToJsonElement(
                    """{"Component_Play_Playinfo":{"oid":"${link.objectId}"}}"""
                ),
                Json.parseToJsonElement(sent.form.getValue("data")),
            )
            request.resolve(true)
            assertEquals(2, web.requests.size)
            assertTrue(web.requests.all { it.url == sent.url })
        }

    @Test
    fun `reads metadata and stream fallback`() = runTest {
        web.respond = { json(response) }
        val video = web.api().fetchLinkedVideo(link)
        assertEquals(61, video.duration)
        assertEquals("https://wx1.sinaimg.cn/cover.jpg", video.coverUrl)
        assertEquals(3, video.streamUrls.size)
        web.respond = {
            json(
                """{"code":"100000","data":{"Component_Play_Playinfo":{"oid":"${link.objectId}","object_type":"video","stream_url":"//media.test/fallback.mp4"}}}"""
            )
        }
        assertEquals(
            listOf("https://media.test/fallback.mp4"),
            web.api().fetchLinkedVideo(link).streamUrls,
        )
    }

    @Test
    fun `missing rejected and mismatched videos fail without extra requests`() = runTest {
        for (body in
            listOf(
                """{"code":"failed"}""",
                """{"code":"100000","data":{"Component_Play_Playinfo":{}}}""",
                """{"code":"100000","data":{"Component_Play_Playinfo":{"oid":"${link.objectId}","object_type":"video"}}}""",
                response.replace(link.objectId, "1034:5000000000000002"),
            )) {
            web.respond = { json(body) }
            val count = web.requests.size
            assertTrue(
                runCatching { web.api().fetchLinkedVideo(link) }.exceptionOrNull()
                    is WeiboApiException
            )
            assertEquals(count + 1, web.requests.size)
        }
    }
}
