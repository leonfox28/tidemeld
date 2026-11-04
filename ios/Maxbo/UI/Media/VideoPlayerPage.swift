import AVKit
import Observation
import SwiftUI

/// Plays the video of a status, from a URL fresh enough to play: the one the
/// card had while it is, else one from fetching the status again (PLAN §8). A
/// URL the CDN refuses is replaced once, carrying on from where it stopped.
@MainActor @Observable
final class VideoModel {
    private(set) var error: WeiboError?
    private(set) var ready = false
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let request: VideoRequest
    @ObservationIgnored private var api: WeiboAPI?
    @ObservationIgnored private var fetched = false
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// Finding a URL and starting on it; cancelled as the page closes, so a
    /// video still loading doesn't start playing unseen.
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var stopped = false

    init(request: VideoRequest) { self.request = request }

    func start(_ api: WeiboAPI) {
        guard self.api == nil else { return }
        self.api = api
        load(refresh: false, at: .zero)
    }

    /// After a failure: from a URL fetched afresh, as the Kotlin app does.
    func retry() { load(refresh: true, at: player.currentTime()) }

    private func load(refresh: Bool, at time: CMTime) {
        guard !stopped, let api else { return }
        error = nil
        ready = false
        loading?.cancel()
        let request = request
        loading = Task {
            do {
                let known = request.initial?.video(at: request.index)
                let source = try await resolveVideoURL(
                    api, id: request.statusId, index: request.index, known: known, refresh: refresh)
                guard !Task.isCancelled else { return }
                guard let url = URL(string: source.url) else { throw WeiboError.api("视频地址无效") }
                fetched = source.fetched
                await play(url, at: time)
            } catch {
                if !Task.isCancelled { self.error = WeiboError.of(error) }
            }
        }
    }

    private func play(_ url: URL, at time: CMTime) async {
        let item = AVPlayerItem(asset: weiboVideoAsset(url))
        observation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.failed() }
        }
        player.replaceCurrentItem(with: item)
        if time > .zero { await player.seek(to: time) }
        guard !Task.isCancelled else { return }
        ready = true
        player.play()
    }

    // The CDN refused the URL: once from a fetched one, else it's over.
    private func failed() {
        guard !stopped else { return }
        devLog("video failed, fetched=\(fetched)")
        if fetched {
            error = .api("视频播放失败")
        } else {
            load(refresh: true, at: player.currentTime())
        }
    }

    func stop() {
        stopped = true
        loading?.cancel()
        observation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

struct VideoPlayerPage: View {
    let request: VideoRequest

    @Environment(AppGraph.self) private var graph
    @Environment(\.dismiss) private var dismiss
    @State private var model: VideoModel

    init(request: VideoRequest) {
        self.request = request
        _model = State(wrappedValue: VideoModel(request: request))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let error = model.error {
                    ErrorRetry(error: error) { model.retry() }
                } else {
                    SystemPlayer(player: model.player).ignoresSafeArea()
                    if !model.ready { ProgressView().controlSize(.large).tint(.white) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { model.start(graph.api) }
        .onDisappear { model.stop() }
    }
}

/// The system's player, with its own controls, picture in picture and AirPlay.
private struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
