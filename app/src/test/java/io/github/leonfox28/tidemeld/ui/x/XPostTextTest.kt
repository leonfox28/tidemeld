package io.github.leonfox28.tidemeld.ui.x

import io.github.leonfox28.tidemeld.ui.post.PostTextSegment
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Test

class XPostTextTest {
    @Test
    fun `links preserve literal content and keep email addresses plain`() {
        val text = "😀 <tag> @fixture #中文话题 email@example.com https://example.com/a_(b))."
        val runs = xTextSegments(text)
        assertEquals(
            text,
            runs.joinToString("") {
                when (it) {
                    is PostTextSegment.Plain -> it.text
                    is PostTextSegment.Link -> it.text
                    else -> ""
                }
            },
        )
        val links = runs.filterIsInstance<PostTextSegment.Link>()
        assertEquals(3, links.size)
        assertEquals("https://x.com/fixture", links[0].link)
        assertEquals("#中文话题", links[1].link.toHttpUrl().queryParameter("q"))
        assertEquals("https://example.com/a_(b)", links[2].link)
    }
}
