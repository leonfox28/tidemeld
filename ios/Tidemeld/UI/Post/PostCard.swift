import SwiftUI

/// Beside media the text keeps to about a phone's width of line; the media
/// takes the rest.
private let wideMainWidth: CGFloat = 400
private let wideAsideGap: CGFloat = 24
/// With no media, the longest line the text runs to.
private let wideMainAloneWidth: CGFloat = 640
/// From this width a card puts its media beside its text.
let wideCardFrom: CGFloat = 840

/// Shared card geometry; platform adapters supply content and already-bound actions.
struct PostCard<Header: View, Body: View, Aside: View, Footer: View>: View {
    var detail = false
    var activity: String?
    var onOpen: (() -> Void)?
    var replyContext: PostReplyReference? = nil
    let hasAside: Bool
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Body
    @ViewBuilder let aside: () -> Aside
    @ViewBuilder let footer: () -> Footer
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !detail, let activity { ActivityLine(label: activity) }
            if detail {
                header()
                if let replyContext { PostReplyContext(reference: replyContext) }
                content()
                if hasAside { aside() }
            } else {
                PostCardLayout(hasAside: hasAside) {
                    VStack(alignment: .leading, spacing: 8) {
                        header()
                        if let replyContext { PostReplyContext(reference: replyContext) }
                        content()
                    }
                    footer()
                    if hasAside { aside() }
                }
            }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, detail ? 12 : 0)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .onTapGesture { if !detail { onOpen?() } }
    }
}

struct PostReplyReference {
    let target: String
    let onOpen: @MainActor () -> Void
}

/// The platform supplies a label and a bound destination; presentation is shared.
struct PostReplyContext: View {
    let reference: PostReplyReference
    var body: some View {
        Button(action: reference.onOpen) {
            Text(
                "\(Text("回复 ").foregroundStyle(AppTheme.secondary))\(Text(reference.target).foregroundStyle(AppTheme.accent))"
            )
            .font(.footnote).multilineTextAlignment(.leading)
        }.buttonStyle(.plain).accessibilityHint("查看被回复的帖子")
    }
}

struct PostHeader<Avatar: View, Badge: View, Menu: View>: View {
    let name: String
    let metadata: String
    let sourceIcon: Image
    let sourceLabel: String
    var tags: [String] = []
    var onAuthor: (() -> Void)?
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let menu: () -> Menu
    var body: some View {
        HStack(spacing: 10) {
            avatar()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(
                        AppTheme.foreground
                    ).lineLimit(1).onTapGesture { onAuthor?() }
                    badge()
                }
                if !metadata.isEmpty {
                    Text(metadata).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            ForEach(tags, id: \.self) { TagLabel(text: $0) }
            menu()
            sourceIcon.resizable().scaledToFit().frame(width: 16, height: 16)
                .foregroundStyle(AppTheme.secondary).frame(width: 32, height: 32)
                .accessibilityLabel("来源：\(sourceLabel)")
        }
    }
}

struct QuotedPost<Content: View>: View {
    var onOpen: (() -> Void)?
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10)).onTapGesture { onOpen?() }
    }
}

/// A timeline card's text, its counts and its media, if any. Narrow, they go
/// one under another (text, media, counts). Wide, the media goes to the right
/// of the text and counts; the counts come right after the text, or at the foot
/// of the card if the media runs further down.
private struct PostCardLayout: Layout {
    let hasAside: Bool

    private func widths(_ width: CGFloat) -> (wide: Bool, main: CGFloat, aside: CGFloat) {
        // The card's own padding counts towards the width a card is given.
        let wide = width + 32 >= wideCardFrom
        guard wide else { return (false, width, width) }
        let main = min(width, hasAside ? wideMainWidth : wideMainAloneWidth)
        return (true, main, max(0, width - wideAsideGap - main))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let w = widths(width)
        let main = subviews[0].sizeThatFits(ProposedViewSize(width: w.main, height: nil)).height
        let footer = subviews[1].sizeThatFits(ProposedViewSize(width: w.main, height: nil)).height
        let aside =
            subviews.count > 2
            ? subviews[2].sizeThatFits(ProposedViewSize(width: w.aside, height: nil)).height : nil
        if w.wide {
            return CGSize(width: width, height: max(main + footer, aside.map { $0 + 12 } ?? 0))
        }
        return CGSize(width: width, height: main + footer + (aside.map { $0 + 8 } ?? 0))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let w = widths(bounds.width)
        let mainProposal = ProposedViewSize(width: w.main, height: nil)
        let main = subviews[0].sizeThatFits(mainProposal).height
        let footer = subviews[1].sizeThatFits(mainProposal).height
        subviews[0].place(at: bounds.origin, proposal: mainProposal)
        let asideProposal = ProposedViewSize(width: w.aside, height: nil)
        if w.wide {
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.maxY - footer), proposal: mainProposal)
            if subviews.count > 2 {
                subviews[2].place(
                    at: CGPoint(x: bounds.minX + w.main + wideAsideGap, y: bounds.minY),
                    proposal: asideProposal)
            }
        } else {
            var y = bounds.minY + main
            if subviews.count > 2 {
                let aside = subviews[2].sizeThatFits(asideProposal).height
                subviews[2].place(at: CGPoint(x: bounds.minX, y: y + 8), proposal: asideProposal)
                y += 8 + aside
            }
            subviews[1].place(at: CGPoint(x: bounds.minX, y: y), proposal: mainProposal)
        }
    }
}

/// Activity context above the card, distinct from the original author.
private struct ActivityLine: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            if label.contains("赞") {
                Image(systemName: "hand.thumbsup").font(.caption)
            } else if label.contains("评论") {
                Image(systemName: "bubble.right").font(.caption)
            }
            Text(label).font(.footnote).lineLimit(1)
        }
        .foregroundStyle(AppTheme.secondary)
    }
}
