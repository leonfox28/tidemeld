import Testing
import UIKit

@testable import Maxbo

@MainActor
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
}
