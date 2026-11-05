import Foundation
import Testing

@testable import Tidemeld

@Suite struct XReplyPresentationTests {
    private func tweet(_ legacy: [String: JSON], note: JSON? = nil, id: String = "42") -> JSON {
        var fields: [String: JSON] = [
            "rest_id": .string(id),
            "core": .object([
                "user_results": .object([
                    "result": .object([
                        "core": .object(["name": .string("合成作者"), "screen_name": .string("fixture")])
                    ])
                ])
            ]),
            "legacy": .object(legacy),
        ]
        if let note { fields["note_tweet"] = .object(["note_tweet_results": .object(["result": note])]) }
        return .object(fields)
    }

    private var photo: JSON {
        .object([
            "type": .string("photo"), "url": .string("https://t.co/photo"),
            "media_url_https": .string("https://media.test/photo.jpg"),
        ])
    }

    @Test func replyAddressingAndAttachmentLinksHaveSeparatePresentations() throws {
        let raw = "@parent @Other 😀 &amp; @body https://t.co/article https://t.co/photo"
        let post = try #require(
            parseXPost(
                tweet([
                    "full_text": .string(raw), "in_reply_to_status_id_str": .string("7"),
                    "in_reply_to_screen_name": .string("parent"),
                    "display_text_range": .array([.int(15), .int(Int64(raw.utf16.count))]),
                    "entities": .object([
                        "urls": .array([
                            .object([
                                "url": .string("https://t.co/article"),
                                "expanded_url": .string("https://example.com/article"),
                            ])
                        ])
                    ]),
                    "extended_entities": .object(["media": .array([photo])]),
                ])))
        #expect(post.text == "😀 & @body https://example.com/article")
        #expect(post.replyToHandles == ["parent", "Other"])
        #expect(post.replyTo == "7")
        #expect(post.media.count == 1)
    }

    @Test func invalidRangesAndLegacyPreviewsNeverTruncateContentOrUnavailableMedia() throws {
        let raw = "@parent 😀 https://t.co/photo-more https://t.co/missing https://t.co/photo"
        var legacy: [String: JSON] = [
            "full_text": .string(raw), "in_reply_to_status_id_str": .string("7"),
            "in_reply_to_screen_name": .string("parent"),
            "display_text_range": .array([.int(9), .int(Int64(raw.utf16.count))]),
            "extended_entities": .object([
                "media": .array([
                    photo,
                    .object(["type": .string("photo"), "url": .string("https://t.co/missing")]),
                ])
            ]),
        ]
        #expect(parseXPost(tweet(legacy))?.text == "@parent 😀 https://t.co/photo-more https://t.co/missing")
        let note: JSON = .object(["text": .string("😀 Long text @body https://t.co/photo"), "entity_set": .object([:])])
        #expect(parseXPost(tweet(legacy, note: note))?.text == "😀 Long text @body")
        legacy["in_reply_to_status_id_str"] = nil
        legacy["display_text_range"] = nil
        #expect(parseXPost(tweet(legacy))?.text.hasPrefix("@parent 😀") == true)
        for kind in ["video", "animated_gif"] {
            let video = tweet([
                "full_text": .string("https://t.co/video"),
                "extended_entities": .object([
                    "media": .array([
                        .object([
                            "type": .string(kind), "url": .string("https://t.co/video"),
                            "media_url_https": .string("https://media.test/cover.jpg"),
                        ])
                    ])
                ]),
            ])
            #expect(parseXPost(video)?.text == "")
        }
    }

    @Test func repostsAndQuotesKeepTheOriginalReplyContext() throws {
        let raw = "@parent Reply https://t.co/photo"
        let reply = tweet([
            "full_text": .string(raw), "in_reply_to_status_id_str": .string("7"),
            "in_reply_to_screen_name": .string("parent"),
            "display_text_range": .array([.int(8), .int(Int64(raw.utf16.count))]),
            "extended_entities": .object(["media": .array([photo])]),
        ])
        let repost = try #require(
            parseXPost(
                tweet(
                    [
                        "retweeted_status_result": .object(["result": reply])
                    ], id: "99")))
        #expect(repost.id == "99")
        #expect(repost.originalID == "42")
        #expect(repost.replyTo == "7")
        #expect(repost.replyToHandles == ["parent"])
        #expect(repost.text == "Reply")
        var quoted = try #require(tweet([:], id: "100").object)
        quoted["quoted_status_result"] = .object(["result": reply])
        #expect(parseXPost(.object(quoted))?.quote?.post.text == "Reply")
        #expect(parseXPost(.object(quoted))?.quote?.post.replyToHandles == ["parent"])
    }

    @MainActor @Test func parentNavigationKeepsTheSourceAccount() throws {
        let router = Router()
        let reference = try #require(
            xReplyReference("7", handles: ["parent"], owner: "x:other", originalID: "42", router: router))
        #expect(reference.target == "@parent")
        reference.onOpen()
        #expect(router.paths[.home] == [.xStatus(owner: "x:other", id: "7", initial: nil)])
        #expect(xReplyReference("42", handles: [], owner: "x:other", originalID: "42", router: router) == nil)
    }

    @MainActor @Test func quotedDetailStartsWithTheCompleteOriginalPost() throws {
        var original = try #require(tweet([
            "full_text": .string("Original https://t.co/photo"),
            "created_at": .string("Thu Nov 05 10:00:00 +0000 2026"),
            "favorite_count": .int(12), "retweet_count": .int(3), "reply_count": .int(2),
            "favorited": .bool(true), "retweeted": .bool(true),
            "in_reply_to_status_id_str": .string("7"),
            "in_reply_to_screen_name": .string("parent"),
            "extended_entities": .object(["media": .array([photo])]),
        ]).object)
        original["core"] = .object([
            "user_results": .object([
                "result": .object([
                    "core": .object(["name": .string("原作者"), "screen_name": .string("original")]),
                    "avatar": .object(["image_url": .string("https://media.test/avatar.jpg")]),
                ])
            ])
        ])
        original["quoted_status_result"] = .object([
            "result": tweet(["full_text": .string("Nested quote")], id: "8")
        ])
        var outer = try #require(tweet(["full_text": .string("Outer")], id: "100").object)
        outer["quoted_status_result"] = .object(["result": .object(original)])
        let quote = try #require(parseXPost(.object(outer))?.quote?.post)
        let model = XDetailModel(initial: quote)
        let initial = try #require(model.post)
        #expect(initial.id == "42")
        #expect(initial.originalID == "42")
        #expect(initial.author == "原作者")
        #expect(initial.handle == "original")
        #expect(initial.avatar == "https://media.test/avatar.jpg")
        #expect(initial.createdAt == parseWeiboDate("Thu Nov 05 10:00:00 +0000 2026"))
        #expect(initial.createdAt != nil)
        #expect(initial.text == "Original")
        #expect(initial.media.count == 1)
        #expect(initial.pictures.first?.viewerVariant.url == "https://media.test/photo.jpg")
        #expect(initial.metrics == XMetrics(likes: 12, reposts: 3, replies: 2, liked: true, reposted: true))
        #expect(initial.replyTo == "7")
        #expect(initial.replyToHandles == ["parent"])
        #expect(initial.quote?.post.originalID == "8")
        #expect(initial.quote?.post.text == "Nested quote")
        #expect(initial.repostedBy == nil)
        #expect(model.replies == nil)
    }
}
