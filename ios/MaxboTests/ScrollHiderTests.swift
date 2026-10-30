import CoreGraphics
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
}
