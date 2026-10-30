import Foundation
import Testing

@testable import Maxbo

/// A compact, comparable rendering of segments.
private func describe(_ segments: [TextSegment]) -> [String] {
    segments.map { s in
        switch s {
        case .plain(let text): "text:\(text)"
        case .emoticon(let url, let alt): "emoticon:\(alt)@\(url)"
        case .expand: "expand"
        case .link(let text, let link, let icon):
            "link:\(text)→"
                + {
                    switch link {
                    case .mention(let name): "user:\(name)"
                    case .topic(let topic): "topic:\(topic)"
                    case .image(let url, _): "image:\(url.absoluteString)"
                    case .web(let url): "web:\(url.absoluteString)"
                    }
                }() + (icon == nil ? "" : " icon")
        }
    }
}

struct StatusTextParserTests {
    @Test func plainTextWithLineBreaksAndEntities() {
        #expect(describe(parseStatusText("第一行<br />第二行 &amp; &lt;b&gt;")) == ["text:第一行\n第二行 & <b>"])
    }

    @Test func mentionsWithUnquotedHref() {
        #expect(
            describe(parseStatusText("你好<a href=/n/示例用户 usercard=\"name=示例用户\">@示例用户</a> 再见"))
                == ["text:你好", "link:@示例用户→user:示例用户", "text: 再见"])
    }

    @Test func topicsLinkByTheirLabel() {
        #expect(
            describe(parseStatusText("<a href=\"//s.weibo.com/weibo?q=%23示例话题%23\" target=\"_blank\">#示例话题#</a>"))
                == ["link:#示例话题#→topic:示例话题"])
    }

    @Test func emoticonsBecomeImagesWithTheirAltText() {
        #expect(
            describe(parseStatusText("好<img alt=\"[笑]\" title=\"[笑]\" src=\"//face.t.sinajs.cn/xiao.png\" />"))
                == ["text:好", "emoticon:[笑]@https://face.t.sinajs.cn/xiao.png"])
        // Without a usable src, the alt text stands in.
        #expect(describe(parseStatusText("<img alt=\"[笑]\" src=\"\">")) == ["text:[笑]"])
    }

    @Test func shortLinksResolveThroughURLStructAndKeepTheirIcon() {
        let urls = [URLEntity(shortURL: "http://t.cn/AbCd", longURL: "https://example.com/article", title: "网页链接")]
        #expect(
            describe(
                parseStatusText(
                    "看 <a target=\"_blank\" href=\"http://t.cn/AbCd\"><img class=\"icon-link\" src=\"https://h5.sinaimg.cn/web.png\"/>网页链接</a>",
                    urls: urls)) == ["text:看 ", "link:网页链接→web:https://example.com/article icon"])
        // An unknown short link opens as is.
        #expect(describe(parseStatusText("<a href=\"http://t.cn/Zz\">网页链接</a>")) == ["link:网页链接→web:http://t.cn/Zz"])
    }

    @Test func leavesOutLinksToHiddenPicturesWithTheirLabels() {
        #expect(
            describe(
                parseStatusText(
                    "图片评论 <a data-pid=p1 href=https://wx1.sinaimg.cn/large/p1.jpg>查看图片</a>"
                        + "<a data-pid=p2 href=https://wx1.sinaimg.cn/large/p2.jpg>查看图片</a>",
                    hiddenPictures: ["p1"]))
                == ["text:图片评论 ", "link:查看图片→image:https://wx1.sinaimg.cn/large/p2.jpg"])
    }

    @Test func pictureLinksAndAppOnlyLinks() {
        #expect(
            describe(
                parseStatusText(
                    "<a target=\"_blank\" data-pid=\"p1\" href=\"https://wx1.sinaimg.cn/large/p1.jpg\">查看图片</a>"
                        + "<a href=\"sinaweibo://searchall?q=x\">打开客户端</a>"))
                == ["link:查看图片→image:https://wx1.sinaimg.cn/large/p1.jpg", "text:打开客户端"])
    }

    @Test func pictureLinksWithoutURLStructOpenPicturesBuiltFromTheirPidsOrTheLink() {
        func pics(_ html: String) -> [String] {
            guard case .link(_, .image(_, let pics), _)? = parseStatusText(html).first(where: {
                if case .link = $0 { true } else { false }
            }) else { return ["not a picture link"] }
            return pics.map(\.viewerVariant.url)
        }
        let first = "0123456ABy1abcdefghijk0000000001"
        let second = "0123456ABy1abcdefghijk0000000002"
        #expect(
            pics("<a data-pids=\(first),\(second) href=https://wx1.sinaimg.cn/large/\(first).jpg>查看2张图片</a>")
                .map { String($0.split(separator: ".cn/").last!) } == ["large/\(first).jpg", "large/\(second).jpg"])
        // Older pids can't be built on; the link stands for its picture.
        #expect(
            pics("<a data-pid=p1 href=https://wx1.sinaimg.cn/large/p1.jpg>查看图片</a>")
                == ["https://wx1.sinaimg.cn/large/p1.jpg"])
        #expect(pics("<a data-pid=p1 href=https://example.com/p1>查看图片</a>") == [])
    }

    @Test func aTruncatedPostEndsWithExpand() {
        #expect(describe(parseStatusText("很长的内容...<span class=\"expand\">展开</span>")) == ["text:很长的内容...", "expand"])
    }

    @Test func unknownElementsKeepTheirText() {
        #expect(describe(parseStatusText("<b>粗</b><span>体</span>")) == ["text:粗体"])
    }

    @Test func plainStatusTextFlattensABodyToOneLine() {
        #expect(
            plainStatusText(
                "看<a href=/n/某人 usercard=\"name=某人\">@某人</a> "
                    + "<img alt=\"[doge]\" src=\"https://face.t.sinajs.cn/doge.png\">"
                    + "<br>第二行<span class=\"expand\">展开</span>") == "看@某人 [doge] 第二行")
    }

    @Test func toleratesBrokenMarkup() {
        // An unclosed link keeps its text; a stray end tag and a lone < are text.
        #expect(describe(parseStatusText("a < b</i><a href=/n/x>@x")) == ["text:a < b", "link:@x→user:x"])
        #expect(describe(parseStatusText("&#20320;&#x597D;&unknown; &amp")) == ["text:你好&unknown; &"])
    }
}
