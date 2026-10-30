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
    private var pulling = false

    /// Starts refreshing, unless it already is; false if the list has no
    /// refresh control, for the caller to refresh some other way.
    func begin() -> Bool {
        guard let scrollView, let control = scrollView.refreshControl else { return false }
        guard !control.isRefreshing, !pulling else { return true }
        // The content moves down first, the control following it as on a
        // pull, and spins once there: started at once, it would show where it
        // spins, over the content still moving down.
        pulling = true
        let shown = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top - control.frame.height)
        scrollView.setContentOffset(shown, animated: true)
        Task {
            // About as long as the scroll takes.
            try? await Task.sleep(for: .milliseconds(300))
            pulling = false
            control.beginRefreshing()
            control.sendActions(for: .valueChanged)
        }
        return true
    }

    /// The list's scroll view: the nearest to [anchor] with a refresh control.
    private var scrollView: UIScrollView? {
        var view = anchor
        while let ancestor = view {
            if let found = ancestor.refreshingScrollView { return found }
            view = ancestor.superview
        }
        return nil
    }
}

extension UIView {
    /// This view, or the first under it, that refreshes on a pull.
    fileprivate var refreshingScrollView: UIScrollView? {
        if let scrollView = self as? UIScrollView, scrollView.refreshControl != nil { return scrollView }
        for subview in subviews {
            if let found = subview.refreshingScrollView { return found }
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
