import SwiftUI

/// Appearance, pictures, and about. Changes apply at once and are kept on the
/// device.
struct SettingsPage: View {
    @Environment(AppGraph.self) private var graph
    @State private var cacheSize: String = "计算中…"
    @State private var confirmingClear = false

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
                        VStack(alignment: .leading) {
                            Text(quality.label)
                            Text(quality.description).font(.caption).foregroundStyle(AppTheme.secondary)
                        }
                        .tag(quality)
                    }
                } label: {
                    Text("图片质量")
                }
                .pickerStyle(.navigationLink)
                Toggle(isOn: binding(\.autoplayLivePhotos)) {
                    Text("自动播放实况照片")
                    Text("查看大图时静音播放一遍，每张要下载几 MB")
                }
                Picker(selection: binding(\.imageCacheLimitMB)) {
                    ForEach(AppSettings.imageCacheLimitChoices, id: \.self) { mb in
                        Text(formatBytes(Int64(mb) * 1024 * 1024)).tag(mb)
                    }
                } label: {
                    Text("图片缓存上限")
                    Text("超出后先删最早下载的图片")
                }
                Button("清除图片缓存") { confirmingClear = true }
                    .badge(Text(cacheSize))
            } header: {
                Text("图片")
            }
            .listRowBackground(AppTheme.surface)
            Section("其他") {
                NavigationLink("关于 maxbo", value: Route.about)
            }
            .listRowBackground(AppTheme.surface)
        }
        .appListStyle()
        .tabBarFollowsScroll()
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { measureCache() }
        .confirmationDialog("清除图片缓存", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                graph.images.clear()
                measureCache()
                graph.toasts.show("图片缓存已清除")
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
            StatusCard(status: samples.0).readingWidth().statusRow()
            CommentTile(comment: samples.1).readingWidth().responseRow()
        }
        .listStyle(.plain)
        .appListStyle()
        .tabBarFollowsScroll()
        // Samples only: their like buttons and links do nothing.
        .allowsHitTesting(false)
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
                id: "text-size-sample", user: WeiboUser(id: "text-size-sample", screenName: "maxbo"),
                createdAt: now.addingTimeInterval(-120),
                text: "拖动下面的滑块调整字体大小，这条微博和下面的评论会按选中的大小显示。调整后所有页面的文字都会跟着变大或变小。",
                repostsCount: 3, commentsCount: 12, likesCount: 46),
            Comment(
                id: "text-size-sample", user: WeiboUser(id: "text-size-sample-2", screenName: "示例用户"),
                createdAt: now.addingTimeInterval(-60), text: "「标准」就是系统设置里的字体大小。", likesCount: 5)
        )
    }
}
