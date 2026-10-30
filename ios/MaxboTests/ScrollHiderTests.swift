import SwiftUI
import Testing

@testable import Maxbo

struct ScrollHiderTests {
    private func after(_ offsets: [CGFloat]) -> ScrollHider {
        var hider = ScrollHider()
        for offset in offsets { hider.scrolled(to: offset) }
        return hider
    }

    @Test func hidesOnceTheContentScrollsOnPastTheThreshold() {
        #expect(after([5, 10, 20]).visible)
        #expect(!after([5, 10, 20, 30]).visible)
    }

    @Test func comesBackAsTheContentScrollsBack() {
        #expect(!after([100, 200, 190]).visible)
        #expect(after([100, 200, 190, 170]).visible)
    }

    @Test func aTurnMeasuresFromWhereItTurned() {
        // Down to 200 hides; back up to 180, then down again: 180 → 200 is not
        // yet past the threshold from the turn at 180.
        var hider = ScrollHider()
        for offset: CGFloat in [100, 200] { hider.scrolled(to: offset) }
        #expect(!hider.visible)
        for offset: CGFloat in [150, 120] { hider.scrolled(to: offset) }
        #expect(hider.visible)
        hider.scrolled(to: 140)
        #expect(hider.visible)
        hider.scrolled(to: 150)
        #expect(!hider.visible)
    }

    @Test func alwaysShowsAtTheTop() {
        #expect(after([100, 300, 0]).visible)
        #expect(after([100, 300, -20]).visible)
    }

    @Test func theOffsetStopsAtTheEnd() {
        // 1000 of content in 800 under bars of 100 and 80: it ends at 380.
        func offset(_ y: CGFloat, bottom: CGFloat = 80) -> CGFloat {
            ScrollGeometry(
                contentOffset: CGPoint(x: 0, y: y), contentSize: CGSize(width: 400, height: 1000),
                contentInsets: EdgeInsets(top: 100, leading: 0, bottom: bottom, trailing: 0),
                containerSize: CGSize(width: 400, height: 800)
            ).offsetFromTop
        }
        #expect(offset(-100) == 0)
        #expect(offset(200) == 300)
        #expect(offset(280) == 380)
        #expect(offset(400) == 380)
        // Pulled past the end, then snapping back to it as a bar goes away
        // and the end moves up 3: not scrolling back.
        #expect(!after([offset(200), offset(330), offset(400), offset(277, bottom: 77)]).visible)
    }

    @Test func contentShorterThanThePageNeverHidesThem() {
        let offset = ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: 60), contentSize: CGSize(width: 400, height: 300),
            contentInsets: EdgeInsets(top: 100, leading: 0, bottom: 80, trailing: 0),
            containerSize: CGSize(width: 400, height: 800)
        ).offsetFromTop
        #expect(offset == 0)
        #expect(after([offset]).visible)
    }
}
