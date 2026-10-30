import SwiftUI

/// The pictures of a request, full screen: swipe between them, pinch or
/// double-tap to zoom, tap or swipe down to close.
///
/// A live photo's motion plays over it from its 实况 button or a long press,
/// once and with sound; with the setting on, on its own and muted, once for
/// each picture.
struct ImageViewer: View {
    let request: ViewerRequest

    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var zoomed = false
    @State private var live: LivePhotoPlayer?

    init(request: ViewerRequest) {
        self.request = request
        _index = State(initialValue: request.index)
    }

    var body: some View {
        let pics = request.pics
        TabView(selection: $index) {
            ForEach(pics.indices, id: \.self) { i in
                ViewerPage(
                    pic: pics[i], live: live, onTap: { dismiss() },
                    onLongPress: { if pics[i].liveVideo != nil { live?.play(pics[i]) } },
                    onZoomed: { zoomed = $0 }
                )
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .scrollDisabled(zoomed)
        .background(.black)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            HStack {
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                Spacer()
                if pics.count > 1 {
                    Text("\(index + 1) / \(pics.count)")
                        .font(.subheadline.monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) {
            if let live, pics.indices.contains(index), pics[index].type == .livePhoto {
                LiveButton(live: live, pic: pics[index]).padding(.bottom, 24)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .onAppear {
            if live == nil { live = LivePhotoPlayer(api: graph.api, statusId: request.statusId) }
            autoplay()
        }
        .onChange(of: index) {
            live?.stop()
            autoplay()
        }
        .onDisappear { live?.release() }
    }

    /// With the setting on, plays the motion of the live photo the viewer
    /// settles on, muted.
    private func autoplay() {
        guard graph.settings.settings.autoplayLivePhotos, request.pics.indices.contains(index) else { return }
        let pic = request.pics[index]
        guard pic.liveVideo != nil else { return }
        Task {
            // Settled on it, not swiped past.
            try? await Task.sleep(for: .milliseconds(400))
            if request.pics.indices.contains(index), request.pics[index].id == pic.id { live?.autoplay(pic) }
        }
    }
}

private struct ViewerPage: View {
    let pic: PicInfo
    let live: LivePhotoPlayer?
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onZoomed: (Bool) -> Void

    @Environment(AppGraph.self) private var graph
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        let variant = graph.settings.settings.imageQuality.viewerVariant(pic)
        ZStack {
            if let image {
                ZoomableImage(image: image, onTap: onTap, onLongPress: onLongPress, onZoomed: onZoomed)
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                    Button("重试") { attempt += 1 }.buttonStyle(.glass)
                }
                .foregroundStyle(.white)
            } else {
                // The list's rendition, while the larger one loads.
                WeiboImage(url: pic.variants.first?.url, contentMode: .fit, placeholder: false)
                    .overlay { ProgressView().tint(.white) }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
            }
            if let live, live.current?.id == pic.id {
                PlayerLayerView(player: live.player)
                    .opacity(live.moving ? 1 : 0)
                    .animation(.easeIn(duration: 0.2), value: live.moving)
                    .allowsHitTesting(false)
            }
        }
        .task(id: "\(variant.url)#\(attempt)") {
            failed = false
            do {
                // Full size, short of what would take more memory than a
                // screen's worth of long picture needs.
                image = try await ImageLoader.shared.image(variant.url, maxPixels: 8192)
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

/// The 实况 button: plays the motion, or stops it; shows loading and failure.
private struct LiveButton: View {
    let live: LivePhotoPlayer
    let pic: PicInfo

    var body: some View {
        if pic.liveVideo == nil {
            // No motion to play: only the mark.
            Label("实况", systemImage: "livephoto")
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        } else {
            let playing = live.current?.id == pic.id
            Button {
                if playing { live.stop() } else { live.play(pic) }
            } label: {
                HStack(spacing: 6) {
                    if playing, !live.moving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: playing ? "stop.fill" : "livephoto")
                    }
                    Text(live.failed == pic.id ? "实况加载失败，点击重试" : "实况")
                }
            }
            .buttonStyle(.glass)
        }
    }
}
