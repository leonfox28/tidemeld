package io.github.leonfox28.tidemeld.core.settings

import java.text.Normalizer
import java.util.Locale

/** Literal rules stored only on this device; no regular expressions or remote service. */
object ContentFilter {
    private fun normalized(value: String) =
        Normalizer.normalize(value, Normalizer.Form.NFKC).lowercase(Locale.ROOT)

    fun keywords(value: String): List<String> =
        value
            .lineSequence()
            .map { it.trim().take(200) }
            .filter { it.isNotEmpty() }
            .distinctBy(::normalized)
            .take(100)
            .toList()

    fun matches(text: String, keywords: String): Boolean {
        val normalizedText = normalized(text)
        return keywords(keywords).any { normalizedText.contains(normalized(it)) }
    }
}
