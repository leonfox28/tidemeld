import SwiftUI
import UIKit

/// A picture that zooms by pinching or double-tapping, and pans when zoomed. A
/// long picture starts across the screen's width, at its top.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var onTap: () -> Void = {}
    var onLongPress: (() -> Void)? = nil
    /// Whether the picture is zoomed in, when the pages shouldn't move.
    var onZoomed: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> ZoomView {
        let view = ZoomView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ZoomView, context: Context) {
        context.coordinator.parent = self
        view.show(image)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator {
        var parent: ZoomableImage
        init(parent: ZoomableImage) { self.parent = parent }
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate {
        weak var coordinator: Coordinator?
        private let imageView = UIImageView()
        private var shownSize: CGSize = .zero
        private var zoomed = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            decelerationRate = .fast
            bouncesZoom = true
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)

            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            double.numberOfTapsRequired = 2
            addGestureRecognizer(double)
            let single = UITapGestureRecognizer(target: self, action: #selector(tapped))
            single.require(toFail: double)
            addGestureRecognizer(single)
            let long = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            addGestureRecognizer(long)
        }

        required init?(coder: NSCoder) { fatalError() }

        func show(_ image: UIImage) {
            guard imageView.image !== image else { return }
            imageView.image = image
            if image.images != nil { imageView.startAnimating() }
            shownSize = .zero
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image = imageView.image, bounds.width > 0, bounds.height > 0,
                bounds.size != shownSize
            else { return }
            shownSize = bounds.size
            zoomScale = 1
            // The picture fitted in the screen; zooming in goes up to filling
            // its width (a long picture) or past it.
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
            imageView.frame = CGRect(origin: .zero, size: size)
            contentSize = size
            let fillWidth = bounds.width / size.width
            minimumZoomScale = 1
            maximumZoomScale = max(3, fillWidth * 2)
            let long = image.size.height / image.size.width > 3 * bounds.height / bounds.width
            if long {
                zoomScale = fillWidth
                contentOffset = .zero
            }
            center()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center()
            let isZoomed = zoomScale > minimumZoomScale + 0.01
            if isZoomed != zoomed {
                zoomed = isZoomed
                coordinator?.parent.onZoomed?(isZoomed)
            }
        }

        /// Keeps a picture smaller than the screen in its middle.
        private func center() {
            let x = max(0, (bounds.width - contentSize.width) / 2)
            let y = max(0, (bounds.height - contentSize.height) / 2)
            contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        @objc private func tapped() { coordinator?.parent.onTap() }

        @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { coordinator?.parent.onLongPress?() }
        }

        @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
            if zoomScale > minimumZoomScale + 0.01 {
                setZoomScale(minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale = min(maximumZoomScale, max(2.5, bounds.width / imageView.bounds.width))
                let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
                zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                width: size.width, height: size.height), animated: true)
            }
        }
    }
}
