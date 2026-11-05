import SwiftUI
import Testing
import UIKit

@testable import Tidemeld

@MainActor
@Suite(.serialized)
struct ZoomableImageTests {
    private func shown(_ width: CGFloat, _ height: CGFloat) -> ZoomableImage.ZoomView {
        let view = ZoomableImage.ZoomView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in }
        view.show(image)
        view.layoutIfNeeded()
        return view
    }

    @Test func aPictureTallerThanTheScreenFillsItsWidthUnzoomed() {
        let view = shown(100, 300)

        #expect(view.contentSize == CGSize(width: 400, height: 1200))
        #expect(view.zoomScale == view.minimumZoomScale)
        #expect(view.contentOffset == .zero)
    }

    @Test func otherPicturesFitTheScreen() {
        let view = shown(300, 200)

        #expect(view.contentSize.width == 400)
        #expect(abs(view.contentSize.height - 400.0 * 2 / 3) < 0.01)
        #expect(view.zoomScale == view.minimumZoomScale)
        // In the middle.
        #expect(view.contentOffset.y == -view.contentInset.top)
        #expect(view.contentInset.top > 0)
    }

    @Test func replacingAPreviewPreservesZoomAndScrollPosition() {
        let view = shown(100, 400)
        view.setZoomScale(2, animated: false)
        view.contentOffset = CGPoint(x: 80, y: 350)
        let size = view.contentSize
        let offset = view.contentOffset
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 1600)).image { _ in }
        view.show(image)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(view.zoomScale == 2)
        #expect(view.contentSize == size)
        #expect(view.contentOffset == offset)
    }

    @Test func transitionAlignmentUsesTheVisibleCropOfALongThumbnail() {
        let thumbnail = TransitionImage.ThumbnailView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 400)).image { _ in }
        let fullFrame = CGRect(x: 0, y: 0, width: 400, height: 1600)
        thumbnail.show(image, fill: true, top: true)
        let top = thumbnail.alignmentRect(in: fullFrame)
        #expect(top.minY == 0)
        #expect(top.width == 400)
        #expect(abs(top.height - 200.0 / 120 * 400) < 0.01)

        thumbnail.show(image, fill: true, top: false)
        let centered = thumbnail.alignmentRect(in: fullFrame)
        #expect(centered.size == top.size)
        #expect(abs(centered.midY - fullFrame.midY) < 0.01)
    }

    @Test func loadingALargerPictureKeepsItsPreviewGeometry() async throws {
        let graph = testGraph(restored: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ViewerImageProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let loader = ImageLoader(directory: directory, limitMB: 1, configuration: configuration)
        let previousLoader = ImageLoader.shared
        ImageLoader.shared = loader
        defer { ImageLoader.shared = previousLoader }
        let preview = PicVariant(url: "https://viewer.invalid/preview", width: 100, height: 400)
        let full = PicVariant(url: "https://viewer.invalid/full", width: 400, height: 1600)
        let pic = PicInfo(id: "long", type: .pic, variants: [preview, full])
        _ = try await loader.image(preview.url, maxPixels: 400)

        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(
            rootView: ImageViewer(request: ViewerRequest(pics: [pic], index: 0)).environment(graph))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
            try? FileManager.default.removeItem(at: directory)
        }
        try await Task.sleep(for: .milliseconds(150))
        let before = try #require(
            zoomView(in: host.view), "The cached preview must use the viewer's layout from its first frame")
        let size = before.contentSize
        let offset = before.contentOffset
        #expect(abs(size.width - before.bounds.width) < 1)
        #expect(size.height > before.bounds.height)
        #expect(offset == .zero)
        try await Task.sleep(for: .seconds(1))
        let after = try #require(zoomView(in: host.view))
        #expect(after === before, "Loading the full picture must retain the same scroll view")
        #expect(after.contentSize == size)
        #expect(after.contentOffset == offset)
    }

    private func zoomView(in view: UIView) -> ZoomableImage.ZoomView? {
        if let zoom = view as? ZoomableImage.ZoomView { return zoom }
        return view.subviews.lazy.compactMap { zoomView(in: $0) }.first
    }

    /// Check the actual intermediate frames: the old full-page alignment
    /// moved a landscape photo up first, then past its destination and back.
    @Test(arguments: ["wide", "portrait", "long"])
    func aSinglePhotoExpandsFromItsThumbnailWithoutDetouring(shape: String) async throws {
        let graph = testGraph(restored: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ViewerImageProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let loader = ImageLoader(directory: directory, limitMB: 1, configuration: configuration)
        let previousLoader = ImageLoader.shared
        ImageLoader.shared = loader
        defer {
            ImageLoader.shared = previousLoader
            try? FileManager.default.removeItem(at: directory)
        }
        let height = shape == "wide" ? 200 : shape == "portrait" ? 600 : 1600
        let variant = PicVariant(url: "https://viewer.invalid/\(shape)", width: 400, height: height)
        let pic = PicInfo(id: shape, type: .pic, variants: [variant])
        _ = try await loader.image(variant.url, maxPixels: 8192)
        _ = try await loader.image(variant.url, maxPixels: 900)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: PhotoTransitionFixture(pic: pic).environment(graph))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .seconds(1))
        func shot() -> UIImage {
            UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
        }
        let before = shot()
        graph.router.viewer = ViewerRequest(pics: [pic], index: 0, sourceID: "source")
        var frames: [UIImage] = []
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(35))
            frames.append(shot())
        }
        try await Task.sleep(for: .milliseconds(300))
        let expanded = shot()
        graph.router.viewer = nil
        var closing: [UIImage] = []
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(35))
            closing.append(shot())
        }
        for _ in 0..<60 {
            if host.presentedViewController == nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(host.presentedViewController == nil, "The native dismissal must finish")
        let returned = shot()

        let source = try #require(redBounds(before))
        let destination = try #require(redBounds(expanded))
        let positions = try (frames + closing).map { try #require(redBounds($0)) }
        #expect(positions.contains { $0.width > source.width + 10 && $0.width < destination.width - 10 })
        for frame in positions {
            // Allow antialiasing and the system spring a few points of room.
            #expect(frame.minY >= min(source.minY, destination.minY) - 5)
            #expect(frame.minY <= max(source.minY, destination.minY) + 5)
            #expect(frame.maxY >= min(source.maxY, destination.maxY) - 5)
            #expect(frame.maxY <= max(source.maxY, destination.maxY) + 5)
        }
        let restored = try #require(redBounds(returned))
        #expect(abs(restored.minX - source.minX) < 1)
        #expect(abs(restored.minY - source.minY) < 1)
        #expect(abs(restored.width - source.width) < 1)
        #expect(abs(restored.height - source.height) < 1)

        if let path = ProcessInfo.processInfo.environment["TIDEMELD_PHOTO_SHOTS"] {
            let shots = URL(fileURLWithPath: path).appendingPathComponent(shape)
            try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
            for (i, image) in ([before] + frames + [expanded] + closing + [returned]).enumerated() {
                try image.pngData()?.write(to: shots.appendingPathComponent("\(i).png"))
            }
        }
    }

    private func redBounds(_ image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        // Sample at one pixel per point; analyze after recording, so pixel
        // scanning cannot slow the animation under test.
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap)!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if pixels[offset] > 180, pixels[offset + 1] < 80, pixels[offset + 2] < 80 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

private struct PhotoTransitionFixture: View {
    let pic: PicInfo
    @Environment(AppGraph.self) private var graph
    @Namespace private var media
    @State private var sources = ImageTransitionSources()
    var body: some View {
        @Bindable var router = graph.router
        NavigationStack {
            List {
                Text("合成单图博文").frame(height: 50)
                PostMedia(items: [.pic(pic)], sourceID: { _ in "source" })
            }
            .navigationTitle("照片转场")
        }
        .environment(\.mediaNamespace, media)
        .environment(\.imageTransitionSources, sources)
        .fullScreenCover(item: $router.viewer) { request in
            ImageViewer(request: request)
                .modifier(ZoomTransition(sourceID: "source", namespace: media))
                .environment(\.imageTransitionSources, sources)
        }
    }
}

private final class ViewerImageProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private var work: DispatchWorkItem?

    override func startLoading() {
        guard request.url?.host == "viewer.invalid" else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let work = DispatchWorkItem { [self] in
            let width = request.url?.path == "/preview" ? 100 : 400
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let height =
                request.url?.path == "/wide" ? width / 2 : request.url?.path == "/portrait" ? width * 3 / 2 : width * 4
            let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image {
                context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: width * 2))
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: width * 2, width: width, height: width * 2))
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: image.pngData()!)
            client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + (request.url?.path == "/full" ? 0.6 : 0), execute: work)
    }

    override func stopLoading() { work?.cancel() }
}
