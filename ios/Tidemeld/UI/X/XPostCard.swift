import SwiftUI

struct XPostCard: View {
    let post: XPost
    let owner: String
    var onReply: (() -> Void)? = nil
    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale
    @State private var showingQuote = false
    var body: some View {
        let state = graph.xInteractions.state(owner, post)
        let available = graph.accounts.find(owner).map { !$0.expired } == true && !state.busy
        VStack(alignment: .leading, spacing: 10) {
            if let name = post.repostedBy {
                Text("\(name) 转发").font(.caption).foregroundStyle(AppTheme.secondary)
            }
            HStack(spacing: 10) {
                if let avatar = post.avatar {
                    WeiboImage(url: avatar, maxPixels: 40 * scale).frame(width: 40, height: 40)
                        .clipShape(
                            Circle())
                }
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.author).font(.headline)
                        Text(
                            "@\(post.handle)"
                                + (post.createdAt.map { " · \(formatPostTime($0))" } ?? "")
                        )
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                if post.promoted { Text("广告").font(.caption) }
                Menu {
                    Button("在 X 网页中打开", action: web)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 40)
                }.accessibilityLabel("更多选项")
            }
            Text(post.text).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(
                    Rectangle()
                ).onTapGesture(perform: open)
            if !post.pictures.isEmpty {
                PicGrid(items: post.pictures.map { .pic($0) }) { index in
                    graph.router.viewer = ViewerRequest(pics: post.pictures, index: index)
                }
            }
            if let cover = post.videoCover {
                Button(action: web) {
                    WeiboImage(url: cover, maxPixels: 700).frame(height: 200).clipped().overlay {
                        Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(
                            .white)
                    }
                }.buttonStyle(.plain).accessibilityLabel("在 X 中播放视频")
            }
            if let quote = post.quote {
                Button {
                    graph.router.push(
                        .xStatus(owner: owner, id: quote.url.lastPathComponent, initial: nil))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quote.author).font(.headline)
                        Text(quote.text).font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(
                        AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            HStack {
                Menu {
                    Button(state.metrics.reposted ? "取消转发" : "转发到我的时间线") { write(.repost) }
                    Button("引用转发") { showingQuote = true }
                } label: {
                    Label(
                        "\(state.metrics.reposted ? "已转发" : "转发") \(formatCount(state.metrics.reposts))",
                        systemImage: "arrow.2.squarepath")
                }.disabled(!available).foregroundStyle(
                    state.metrics.reposted ? AppTheme.accent : AppTheme.secondary)
                Spacer(minLength: 8)
                Button(action: onReply ?? open) {
                    Label("评论 \(formatCount(state.metrics.replies))", systemImage: "bubble")
                }
                Spacer(minLength: 8)
                Button {
                    write(.like)
                } label: {
                    Label(
                        "\(state.metrics.liked ? "已赞" : "赞") \(formatCount(state.metrics.likes))",
                        systemImage: state.metrics.liked ? "heart.fill" : "heart")
                }.disabled(!available).foregroundStyle(
                    state.metrics.liked ? AppTheme.accent : AppTheme.secondary)
            }.font(.subheadline).buttonStyle(.borderless).foregroundStyle(AppTheme.secondary).frame(
                minHeight: 40)
            if state.busy { ProgressView().frame(maxWidth: .infinity) }
        }.padding(16)
            .sheet(isPresented: $showingQuote) { XComposer(owner: owner, post: post, quote: true) }
    }
    private func open() {
        graph.router.push(.xStatus(owner: owner, id: post.originalID, initial: post))
    }
    private func web() { graph.router.push(.accountWeb(owner, post.url)) }
    private func write(_ action: XWrite) {
        Task {
            do { try await graph.xInteractions.write(owner, post: post, action: action) } catch {
                graph.toasts.showError(error, router: graph.router)
            }
        }
    }
}
