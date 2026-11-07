import SwiftUI
import Testing
import UIKit

@testable import Tidemeld

@MainActor @Suite(.serialized)
struct PostTextLayoutTests {
    @Test(arguments: [DynamicTypeSize.small, .large, .xxxLarge], [Font.TextStyle.subheadline, .callout])
    func bitmapImagesKeepTheSurroundingTextHeight(typeSize: DynamicTypeSize, style: Font.TextStyle) async throws {
        let previous = ImageLoader.shared
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InlineLayoutImageProtocol.self]
        ImageLoader.shared = ImageLoader(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            limitMB: 1, configuration: configuration)
        defer { ImageLoader.shared = previous }
        let url = "https://inline-layout.invalid/\(UUID()).png"
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle(style), compatibleWith: traits)
        let imageHeight = (font.pointSize * 1.2).rounded()
        InlineImages.shared.load(url, height: imageHeight, scale: 3)
        for _ in 0..<100 {
            if InlineImages.shared.image(url, height: imageHeight) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try #require(InlineImages.shared.image(url, height: imageHeight))
        func size(_ segments: [PostTextSegment]) -> CGSize {
            UIHostingController(rootView: PostText(segments: segments, textStyle: style).dynamicTypeSize(typeSize))
                .sizeThatFits(in: CGSize(width: 1000, height: 10000))
        }
        let plain = size([.plain("Ag 中文回复")])
        let emoticon = PostTextSegment.emoticon(url: url, alt: "[示例表情]")
        let one = size([.plain("Ag 中文回复"), emoticon])
        let two = size([.plain("Ag 中文回复"), emoticon, emoticon])
        let link = size([.plain("Ag 中文回复"), .link("链接", "target", iconURL: url)])
        let multiline = size([.plain("Ag 中文回复"), emoticon, .plain("\nAg 中文回复"), emoticon])
        #expect(abs(one.height - plain.height) < 1, "A loaded bitmap must not inflate a reply's line height")
        #expect(abs(two.height - plain.height) < 1)
        #expect(abs(link.height - plain.height) < 1)
        #expect(abs(multiline.height - size([.plain("Ag 中文回复\nAg 中文回复")]).height) < 1)
        #expect(abs((two.width - one.width) - imageHeight) < 1,
                "Consecutive images must each reserve their own width")

        func paintedPixels(_ segments: [PostTextSegment]) throws -> Int {
            let renderer = ImageRenderer(content: PostText(segments: segments, textStyle: style)
                .dynamicTypeSize(typeSize).frame(width: 400, alignment: .leading)
                .padding(4).background(.white))
            renderer.scale = 3
            let bitmap = try #require(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(
                    data: buffer.baseAddress, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                    bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
            }
            return stride(from: 0, to: pixels.count, by: 4).filter {
                pixels[$0] > 220 && (140..<200).contains(pixels[$0 + 1]) && pixels[$0 + 2] < 60
            }.count
        }
        let onePainted = try paintedPixels([emoticon])
        let twoPainted = try paintedPixels([emoticon, emoticon])
        let side = min(imageHeight, font.lineHeight) * 3
        #expect(Double(onePainted) >= pow(side - 2, 2), "The bitmap must remain fully visible")
        #expect(abs(Double(twoPainted) / Double(max(onePainted, 1)) - 2) < 0.1,
                "Consecutive identical emoticons must both be drawn")
    }

    @Test(arguments: [DynamicTypeSize.small, .large, .xxxLarge], [240.0, 360.0])
    func repliesKeepCompleteLinesUnderShortHeightProposals(typeSize: DynamicTypeSize, width: Double) {
        let segments: [PostTextSegment] = [
            .link("@示例作者", "author"),
            .plain("：" + String(repeating: "合成回复包含中文 English 和表情😂。", count: 6))
        ]
        func height(maxLines: Int?, proposedHeight: CGFloat) -> CGFloat {
            let host = UIHostingController(rootView:
                PostText(segments: segments, textStyle: .subheadline, maxLines: maxLines)
                    .dynamicTypeSize(typeSize))
            return host.sizeThatFits(in: CGSize(width: width, height: proposedHeight)).height
        }

        let fullHeight = height(maxLines: nil, proposedHeight: 10000)
        let twoLines = height(maxLines: 2, proposedHeight: 10000)
        let oneLine = height(maxLines: 1, proposedHeight: 10000)
        #expect(fullHeight > twoLines)
        #expect(twoLines > oneLine)
        for limit in [nil, 2] as [Int?] {
            let expected = limit == nil ? fullHeight : twoLines
            #expect(abs(height(maxLines: limit, proposedHeight: 12) - expected) < 1,
                    "Replies must wrap at the available width and retain complete visible lines")
        }
    }
}

private final class InlineLayoutImageProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAIAAABvFaqvAAAAH0lEQVR4nGN4v1aMKohh1KBRg0YNGjVo1KBRgwbeIAApCNCu2ZoupAAAAABJRU5ErkJggg==")!
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
