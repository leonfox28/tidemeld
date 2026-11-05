import SwiftUI
import Testing
import UIKit

@testable import Tidemeld

struct ScrollHiderTests {
    @MainActor @Test func navigationPreservesTheReadingPagesBarState() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let graph = testGraph(restored: nil)
        let host = UIHostingController(rootView: BarNavigationPage(graph: graph))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(600))
        let tabs = try #require(descendant(of: host, as: UITabBarController.self))
        let scroll = try #require(descendant(of: host.view, as: UIScrollView.self))
        #expect(!tabs.isTabBarHidden)
        #expect(tabs.tabBar.alpha > 0.99)

        let navigation = try #require(descendant(of: host, as: UINavigationController.self))
        #expect(navigation.navigationBar.topItem?.title == "首页")
        #expect(!navigation.isNavigationBarHidden)
        let visibleFrames = BarVisibilityFrames(tabs: tabs)
        defer { visibleFrames.stop() }
        // Navigation covers home without changing the bar's own visibility.
        withAnimation { graph.router.push(.about) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(!tabs.isTabBarHidden)
        #expect(navigation.viewControllers.count == 2)
        #expect(!navigation.isNavigationBarHidden)
        #expect(navigation.navigationBar.topItem?.title == "关于")
        let top = try #require(navigation.topViewController)
        #expect(!tabs.view.isDescendant(of: top.view), "A secondary page must cover the whole TabView")
        withAnimation { graph.router.pop() }
        try await Task.sleep(for: .milliseconds(600))
        #expect(!tabs.isTabBarHidden)
        #expect(tabs.tabBar.alpha > 0.99)

        visibleFrames.stop()
        #expect(!visibleFrames.hidden.isEmpty)
        #expect(
            visibleFrames.hidden.allSatisfy { !$0 }, "A visible bar must travel with home, not hide during navigation")
        #expect(visibleFrames.alphas.allSatisfy { $0 > 0.99 })
        scroll.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        try await Task.sleep(for: .milliseconds(600))
        #expect(tabs.isTabBarHidden)
        withAnimation { graph.router.push(.about) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(tabs.isTabBarHidden)
        let frames = BarVisibilityFrames(tabs: tabs)
        defer { frames.stop() }
        withAnimation { graph.router.pop() }
        try await Task.sleep(for: .milliseconds(800))
        #expect(!frames.hidden.isEmpty)
        #expect(frames.hidden.allSatisfy { $0 }, "Returning to a hidden bar must not show it during the transition")
        frames.stop()
        #expect(tabs.isTabBarHidden)

        // A chain of secondary pages stays outside TabView as well.
        withAnimation { graph.router.push(.about) }
        try await Task.sleep(for: .milliseconds(600))
        withAnimation { graph.router.push(.licenses) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(navigation.viewControllers.count == 3)
        #expect(tabs.isTabBarHidden)
        withAnimation { graph.router.pop() }
        try await Task.sleep(for: .milliseconds(600))
        withAnimation { graph.router.pop() }
        try await Task.sleep(for: .milliseconds(600))
        #expect(tabs.isTabBarHidden)
        scroll.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
        try await Task.sleep(for: .milliseconds(600))
        #expect(!tabs.isTabBarHidden, "Scrolling back must still reveal the bar after returning")
        #expect(tabs.tabBar.alpha > 0.99)
    }

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

    @Test func contentMovedByABarDoesNotCount() {
        // Hidden at the end, where the tab bar going away takes 49 off the
        // inset below and pulls the content back as far.
        var hider = ScrollHider()
        for offset: CGFloat in [100, 300] { hider.scrolled(to: .init(offset: offset, top: 116, bottom: 83)) }
        #expect(!hider.visible)
        hider.scrolled(to: .init(offset: 251, top: 116, bottom: 34))
        #expect(!hider.visible)
        // Scrolling back from there does count.
        hider.scrolled(to: .init(offset: 220, top: 116, bottom: 34))
        #expect(hider.visible)
    }

    @Test func showingMeasuresAgainFromThere() {
        var hider = after([100, 300])
        hider.show()
        #expect(hider.visible)
        // Down from 300 hides it again only past the threshold.
        hider.scrolled(to: 320)
        #expect(hider.visible)
        hider.scrolled(to: 330)
        #expect(!hider.visible)
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

private struct BarNavigationPage: View {
    let graph: AppGraph
    var body: some View {
        AppNavigation {
            TabView {
                Tab("首页", systemImage: "house") {
                    List(0..<80) { index in Text("合成帖子 \(index)").frame(height: 80) }
                        .tabBarHidesOnScroll()
                        .environment(\.isCurrentNavigationPage, graph.router.paths[.home, default: []].isEmpty)
                }
                Tab("设置", systemImage: "gearshape") { Text("设置") }
            }
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
        }.environment(graph)
    }
}

@MainActor private func descendant<T>(of controller: UIViewController, as type: T.Type) -> T? {
    if let result = controller as? T { return result }
    return controller.children.lazy.compactMap { descendant(of: $0, as: type) }.first
}

@MainActor private func descendant<T>(of view: UIView, as type: T.Type) -> T? {
    if let result = view as? T { return result }
    return view.subviews.lazy.compactMap { descendant(of: $0, as: type) }.first
}

@MainActor private final class BarVisibilityFrames: NSObject {
    private let tabs: UITabBarController
    private var link: CADisplayLink?
    private(set) var hidden: [Bool] = []
    private(set) var alphas: [CGFloat] = []
    init(tabs: UITabBarController) {
        self.tabs = tabs
        super.init()
        link = CADisplayLink(target: self, selector: #selector(sample))
        link?.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate() }
    @objc private func sample() {
        hidden.append(tabs.isTabBarHidden)
        alphas.append(tabs.tabBar.alpha)
    }
}
