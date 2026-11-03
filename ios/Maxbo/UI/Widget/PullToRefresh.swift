import SwiftUI
import UIKit

/// Refreshes a list as if pulled down, as tapping the open tab again does at
/// the top: the system's spinner shows above the content, pushing it down,
/// while the list's `.refreshable` action runs, and goes once it returns.
/// SwiftUI has no way to, so this starts the `UIRefreshControl` that
/// `.refreshable` gives the list's UIKit scroll view.
///
/// Only under an inline title: under a large one with a search field, moving
/// the content from code pulls the title down over the field, and leaves the
/// field hidden.
@MainActor
final class PullToRefresh {
    fileprivate weak var anchor: UIView?

    /// Starts refreshing, unless it already is; false if the list has no
    /// refresh control, for the caller to refresh some other way.
    func begin() -> Bool {
        guard let scrollView, let control = scrollView.refreshControl else { return false }
        guard !control.isRefreshing else { return true }
        let shown = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top - control.frame.height)
        // Refreshing first, which makes room for the control above the
        // content: moved down before that, the content is past its top, and
        // the scroll view puts it back on its next layout.
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        scrollView.setContentOffset(shown, animated: true)
        // The control shows where it spins at once, over the content still
        // moving down, so it comes in as the content makes way for it.
        control.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0.1, options: .curveEaseIn) { control.alpha = 1 }
        // Not kept for a list that has gone.
        Task { [weak scrollView, weak control] in
            while control?.isRefreshing == true {
                try? await Task.sleep(for: .milliseconds(16))
            }
            if let scrollView { await settle(scrollView) }
        }
        return true
    }

    /// With the refresh done, moves the content back up if the scroll view
    /// doesn't. It doesn't when the last drag on it ended with the finger at
    /// rest: it goes on counting that drag as under way (a flag of its own,
    /// not `isDragging`), and leaves the content for the finger to let go of,
    /// the control stuck as it goes back and showing nothing the next time.
    private func settle(_ scrollView: UIScrollView) async {
        let ended = scrollView.contentOffset
        // Started on its own, it would be under way by now.
        try? await Task.sleep(for: .milliseconds(50))
        let top = -scrollView.adjustedContentInset.top
        guard scrollView.contentOffset == ended, ended.y < top, !scrollView.isTracking else { return }
        scrollView.setContentOffset(CGPoint(x: ended.x, y: top), animated: true)
    }

    /// The list's scroll view: the nearest to [anchor] with a refresh control
    /// where the anchor is, as lists side by side can share a superview.
    private var scrollView: UIScrollView? {
        guard let anchor else { return nil }
        let center = anchor.convert(CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: nil)
        var view: UIView? = anchor
        while let ancestor = view {
            if let found = ancestor.refreshingScrollView(at: center) { return found }
            view = ancestor.superview
        }
        return nil
    }
}

extension UIView {
    /// This view, or the first under it, that refreshes on a pull and covers
    /// [point], in the window's coordinates.
    fileprivate func refreshingScrollView(at point: CGPoint) -> UIScrollView? {
        if let scrollView = self as? UIScrollView, scrollView.refreshControl != nil,
            scrollView.convert(scrollView.bounds, to: nil).contains(point)
        {
            return scrollView
        }
        for subview in subviews {
            if let found = subview.refreshingScrollView(at: point) { return found }
        }
        return nil
    }
}

extension View {
    /// Lets [pull] refresh this `.refreshable` list as if pulled down.
    func pullToRefresh(_ pull: PullToRefresh) -> some View {
        background(PullAnchor(pull: pull))
    }
}

/// A view beside the list, for [PullToRefresh] to find the list's scroll view
/// from.
private struct PullAnchor: UIViewRepresentable {
    let pull: PullToRefresh

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        pull.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        pull.anchor = view
    }
}
