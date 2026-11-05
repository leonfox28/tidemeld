import SwiftUI
import UIKit

/// The source views are owned by their tiles, never by the transition.
@MainActor final class ImageTransitionSources {
    private let views = NSMapTable<NSString, UIView>(keyOptions: .strongMemory, valueOptions: .weakMemory)

    func register(_ view: UIView, id: String) { views.setObject(view, forKey: id as NSString) }
    func unregister(_ view: UIView, id: String) {
        if views.object(forKey: id as NSString) === view { views.removeObject(forKey: id as NSString) }
    }
    func view(for id: String) -> UIView? {
        guard let view = views.object(forKey: id as NSString), view.window != nil else { return nil }
        return view
    }
}

extension EnvironmentValues {
    @Entry var imageTransitionSources: ImageTransitionSources? = nil
    @Entry var imageTransitionSourceID: String? = nil
}

/// A real image view gives UIKit the thumbnail's exact bounds and pixels.
struct TransitionImage: UIViewRepresentable {
    let image: UIImage
    let contentMode: ContentMode
    let alignment: Alignment
    let sourceID: String
    let sources: ImageTransitionSources

    func makeUIView(context: Context) -> ThumbnailView { ThumbnailView() }
    func updateUIView(_ view: ThumbnailView, context: Context) {
        view.show(image, fill: contentMode == .fill, top: alignment == .top)
        view.register(in: sources, id: sourceID)
    }
    static func dismantleUIView(_ view: ThumbnailView, coordinator: ()) { view.unregister() }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ThumbnailView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    final class ThumbnailView: UIView {
        private let imageView = UIImageView()
        private var fill = true
        private var top = false
        private weak var sources: ImageTransitionSources?
        private var sourceID: String?
        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            layer.cornerRadius = 4
            addSubview(imageView)
        }
        required init?(coder: NSCoder) { fatalError() }
        func register(in sources: ImageTransitionSources, id: String) {
            unregister()
            self.sources = sources
            sourceID = id
            sources.register(self, id: id)
        }
        func unregister() {
            if let sourceID { sources?.unregister(self, id: sourceID) }
        }
        /// The part of the full image visible in the thumbnail. Long pictures
        /// are cropped at the top, so aligning their full height would shift
        /// the starting image away from the tapped tile.
        func alignmentRect(in imageFrame: CGRect) -> CGRect {
            layoutIfNeeded()
            let frame = imageView.frame
            guard frame.width > 0, frame.height > 0 else { return imageFrame }
            let visible = bounds.intersection(frame)
            return CGRect(
                x: imageFrame.minX + (visible.minX - frame.minX) / frame.width * imageFrame.width,
                y: imageFrame.minY + (visible.minY - frame.minY) / frame.height * imageFrame.height,
                width: visible.width / frame.width * imageFrame.width,
                height: visible.height / frame.height * imageFrame.height)
        }
        func show(_ image: UIImage, fill: Bool, top: Bool) {
            if imageView.image !== image {
                imageView.stopAnimating()
                imageView.image = image
                if image.images != nil { imageView.startAnimating() }
            }
            self.fill = fill
            self.top = top
            setNeedsLayout()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }
            let x = bounds.width / image.size.width
            let y = bounds.height / image.size.height
            let scale = fill ? max(x, y) : min(x, y)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(
                x: (bounds.width - size.width) / 2,
                y: top ? 0 : (bounds.height - size.height) / 2,
                width: size.width, height: size.height)
        }
    }
}

/// SwiftUI's zoom aligns the thumbnail to the whole page. UIKit also lets us
/// align it to the image inside that page, keeping the native interactive zoom.
struct ImageTransitionAlignment: UIViewControllerRepresentable {
    let sourceID: String
    let sources: ImageTransitionSources

    func makeUIViewController(context: Context) -> Controller { Controller(sourceID: sourceID, sources: sources) }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        let sourceID: String
        let sources: ImageTransitionSources
        init(sourceID: String, sources: ImageTransitionSources) {
            self.sourceID = sourceID
            self.sources = sources
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            configure()
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            configure()
        }
        private func configure() {
            guard let parent, sources.view(for: sourceID) != nil else { return }
            let options = UIViewController.Transition.ZoomOptions()
            options.alignmentRectProvider = { context in
                let root = context.zoomedViewController.view!
                root.layoutIfNeeded()
                guard let rect = Self.imageRect(in: root, root: root) else { return nil }
                return (context.sourceView as? TransitionImage.ThumbnailView)?.alignmentRect(in: rect) ?? rect
            }
            parent.preferredTransition = .zoom(options: options) { [sources, sourceID] _ in
                sources.view(for: sourceID)
            }
        }
        private static func imageRect(in view: UIView, root: UIView) -> CGRect? {
            if let zoom = view as? ZoomableImage.ZoomView,
                zoom.convert(zoom.bounds, to: root).contains(CGPoint(x: root.bounds.midX, y: root.bounds.midY))
            {
                return zoom.imageFrame(in: root)
            }
            return view.subviews.lazy.compactMap { imageRect(in: $0, root: root) }.first
        }
    }
}
