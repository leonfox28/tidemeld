import SwiftUI

/// The settings tab: appearance, pictures, app information and session actions.
struct SettingsPage: View {
    @Environment(AppGraph.self) private var graph
    @State private var cacheSize: String = "计算中…"
    @State private var confirmingClear = false
    @State private var editingFilters = false

    var body: some View {
        let controller = graph.settings
        let settings = controller.settings
        Form {
            Section("外观") {
                Picker("主题", selection: binding(\.themeMode)) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
                NavigationLink(value: Route.textSize) {
                    LabeledContent("字体大小", value: settings.textSize.label)
                }
            }
            .listRowBackground(AppTheme.surface)
            Section {
                Picker(selection: binding(\.imageQuality)) {
                    ForEach(ImageQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                } label: {
                    Text("图片质量")
                }
                .pickerStyle(.navigationLink)
                Toggle("自动播放实况照片", isOn: binding(\.autoplayLivePhotos))
                Picker(selection: binding(\.imageCacheLimitMB)) {
                    ForEach(AppSettings.imageCacheLimitChoices, id: \.self) { mb in
                        Text(formatBytes(Int64(mb) * 1024 * 1024)).tag(mb)
                    }
                } label: {
                    Text("图片缓存上限")
                }
                Button("清除图片缓存") { confirmingClear = true }
                    .badge(Text(cacheSize))
            } header: {
                Text("图片")
            }
            .listRowBackground(AppTheme.surface)
            Section("内容") {
                Button { editingFilters = true } label: {
                    LabeledContent("内容过滤", value: "\(ContentFilter.keywords(settings.filterKeywords).count) 个关键词")
                }
            }.listRowBackground(AppTheme.surface)
            Section("其他") {
                NavigationLink("关于叠澜", value: Route.about)
                #if DEBUG
                NavigationLink("开发者诊断", value: Route.diagnostics)
                #endif
            }
            .listRowBackground(AppTheme.surface)
            Section("账号") {
                NavigationLink("账号管理", value: Route.accounts)
            }
            .listRowBackground(AppTheme.surface)
        }
        .appListStyle()
        .tabBarHidesOnScroll()
        .sheet(isPresented: $editingFilters) { ContentFilterEditor() }
        .task { measureCache() }
        // A lower limit drops pictures, which the cache does in its own time,
        // so looked at again a moment later; the Kotlin page reads it again
        // too.
        .task(id: graph.settings.settings.imageCacheLimitMB) {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { measureCache() }
        }
        .confirmationDialog("清除图片缓存", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                Task {
                    await graph.images.clear()
                    measureCache()
                    graph.toasts.show("图片缓存已清除")
                }
            }
        } message: {
            Text("已下载的图片会被删除，之后浏览时重新下载。")
        }

    }

    private func binding<V>(_ key: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(
            get: { graph.settings.settings[keyPath: key] },
            set: { value in graph.settings.update { $0[keyPath: key] = value } })
    }

    private func measureCache() {
        cacheSize = "已用 \(formatBytes(Int64(graph.images.diskUsage)))"
    }
}

private struct ContentFilterEditor: View {
    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft).frame(minHeight: 180)
                        .accessibilityLabel("过滤关键词，每行一个")
                } header: { Text("关键词，每行一个") } footer: {
                    Text("命中正文、作者、引用或回复预览时折叠整条内容，不区分大小写。最多 100 个，每个最多 200 字。规则仅保存在本机，作用于原生微博与 X 帖子、评论；不改变平台账号设置，也不影响网页内容。")
                }
                Section {
                    Label("敏感媒体默认隐藏", systemImage: "eye.slash")
                    Text("X 标记为敏感的图片和视频默认不加载。可以在对应内容处单独显示，再次进入时恢复隐藏。")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                }
            }.navigationTitle("内容过滤").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let keywords = ContentFilter.keywords(draft).joined(separator: "\n")
                            graph.settings.update { $0.filterKeywords = keywords }
                            dismiss()
                        }
                    }
                }
        }.onAppear { draft = graph.settings.settings.filterKeywords }
    }
}

/// Picks the text size on a slider, under a sample post and comment that show
/// it. A new size applies at once, here as everywhere, so the samples are the
/// app itself at that size.
struct TextSizePage: View {
    @Environment(AppGraph.self) private var graph
    @State private var samples = TextSizePage.makeSamples()

    var body: some View {
        let size = graph.settings.settings.textSize
        let sizes = TextSize.allCases
        let index = sizes.firstIndex(of: size)!
        List {
            // Samples only: their like buttons and links do nothing. The list
            // still scrolls, so the largest sizes can be seen in full.
            StatusCard(status: samples.0).allowsHitTesting(false).readingWidth().statusRow()
            CommentTile(comment: samples.1).allowsHitTesting(false).readingWidth().responseRow()
        }
        .listStyle(.plain)
        .appListStyle()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text(size.label).font(.headline)
                HStack(spacing: 12) {
                    Button("调小") { choose(index - 1) }
                        .font(.system(size: 14, weight: .medium))
                        .disabled(index == 0)
                    Slider(
                        value: Binding(get: { Double(index) }, set: { choose(Int($0.rounded())) }),
                        in: 0...Double(sizes.count - 1), step: 1
                    )
                    .accessibilityValue(size.label)
                    Button("调大") { choose(index + 1) }
                        .font(.system(size: 22, weight: .medium))
                        .disabled(index == sizes.count - 1)
                }
                .labelStyle(.titleOnly)
            }
            // A size of its own, so the slider stays where the finger is.
            .dynamicTypeSize(.large)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(.horizontal, 16)
            .frame(maxWidth: 640)
        }
        .navigationTitle("字体大小")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ index: Int) {
        let sizes = TextSize.allCases
        guard sizes.indices.contains(index) else { return }
        graph.settings.update { $0.textSize = sizes[index] }
    }

    private static func makeSamples() -> (Status, Comment) {
        let now = Date()
        return (
            Status(
                id: "text-size-sample", user: WeiboUser(id: "text-size-sample", screenName: "叠澜"),
                createdAt: now.addingTimeInterval(-120),
                text: "拖动下面的滑块调整字体大小，这条微博和下面的评论会按选中的大小显示。调整后所有页面的文字都会跟着变大或变小。",
                repostsCount: 3, commentsCount: 12, likesCount: 46),
            Comment(
                id: "text-size-sample", user: WeiboUser(id: "text-size-sample-2", screenName: "示例用户"),
                createdAt: now.addingTimeInterval(-60), text: "「标准」就是系统设置里的字体大小。", likesCount: 5)
        )
    }
}
