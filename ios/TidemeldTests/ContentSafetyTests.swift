import Foundation
import Testing
@testable import Tidemeld

@Suite struct ContentSafetyTests {
    private func tweet(_ legacy: String, id: String = "42", quote: String = "") -> String {
        """
        {"rest_id":"\(id)","core":{"user_results":{"result":{"core":{"name":"合成作者","screen_name":"fixture"}}}},"legacy":\(legacy)\(quote)}
        """
    }

    @Test func sensitivitySurvivesQuotesRepostsAndVisibilityWrappers() throws {
        let marked = tweet(#"{"full_text":"合成内容","possibly_sensitive":true}"#)
        let post = try #require(parseXPost(JSON.parse(marked)))
        #expect(post.sensitive)
        #expect(parseXPost(JSON.parse("{\"tweet\":\(marked)}"))?.sensitive == true)
        let repost = tweet("{\"retweeted_status_result\":{\"result\":\(marked)}}", id: "43")
        #expect(parseXPost(JSON.parse(repost))?.sensitive == true)
        let quote = tweet("{}", id: "44", quote: ",\"quoted_status_result\":{\"result\":\(marked)}")
        let outer = try #require(parseXPost(JSON.parse(quote)))
        #expect(!outer.sensitive)
        #expect(outer.quote?.post.sensitive == true)
        for key in ["adult_content", "graphic_violence", "other"] {
            let media = tweet("{\"extended_entities\":{\"media\":[{\"sensitive_media_warning\":{\"\(key)\":true}}]}}")
            #expect(parseXPost(JSON.parse(media))?.sensitive == true)
        }
        #expect(parseXPost(JSON.parse(tweet(#"{"possibly_sensitive":false}"#)))?.sensitive == false)
    }

    @Test func literalFiltersNormalizeWidthAndCaseAndCoverNestedContent() {
        let rules = "  ａｂＣ  \nABC\n\n合成词\n[字面]"
        #expect(ContentFilter.keywords(rules).count == 3)
        #expect(ContentFilter.matches("About AbC", keywords: rules))
        #expect(ContentFilter.matches("这是合成词", keywords: rules))
        #expect(!ContentFilter.matches("字面", keywords: rules))
        #expect(!ContentFilter.matches("任何内容", keywords: "  \n"))
        let nested = Status(id: "2", text: "<b>合成词</b>")
        let parent = Status(id: "1", text: "普通正文", retweeted: nested)
        #expect(ContentFilter.matches(parent.contentFilterText, keywords: rules))
    }

    @Test func filtersPersistWithoutChangingExistingSettings() throws {
        let suite = "ContentSafetyTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = DefaultsSettingsStorage(defaults: defaults)
        #expect(storage.load().filterKeywords.isEmpty)
        var settings = storage.load()
        settings.themeMode = .dark
        settings.filterKeywords = "合成词\nExample"
        storage.save(settings)
        #expect(storage.load() == settings)
    }
}
