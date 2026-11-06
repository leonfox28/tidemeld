package io.github.leonfox28.tidemeld.core.settings

import org.junit.Assert.*
import org.junit.Test

class ContentFilterTest {
    @Test
    fun `literal rules normalize width and case without treating input as regex`() {
        val rules = "  ａｂＣ  \nABC\n\n合成词\n[字面]"
        assertEquals(3, ContentFilter.keywords(rules).size)
        assertTrue(ContentFilter.matches("About AbC", rules))
        assertTrue(ContentFilter.matches("这是合成词", rules))
        assertFalse(ContentFilter.matches("字面", rules))
        assertFalse(ContentFilter.matches("任何内容", "  \n"))
    }
}
