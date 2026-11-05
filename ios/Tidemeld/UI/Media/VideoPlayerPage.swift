import AVKit
import Observation
import SwiftUI

/// Shared player: the adapter resolves URLs and refreshes a rejected source once.
@MainActor @Observable
final class VideoModel {
    private(set) var error: WeiboError?
    private(set) var ready = false
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let request: VideoRequest
    @ObservationIgnored private var started = false
    @ObservationIgnored private var fetched = false
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var videoAsset: MediaVideoAsset?
    /// Finding a URL and starting on it; cancelled as the page closes, so a
    /// video still loading doesn't start playing unseen.
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var stopped = false

    init(request: VideoRequest) {
        self.request = request
        // AVFoundation cannot predict download speed for a custom loader.
        player.automaticallyWaitsToMinimizeStalling = false
        // An AirPlay receiver cannot use our in-process resource loader.
        player.allowsExternalPlayback = false
    }

    func start() {
        guard !started else { return }
        started = true
        load(refresh: false, at: .zero)
    }

    /// After a failure: from a URL fetched afresh, as the Kotlin app does.
    func retry() { load(refresh: true, at: player.currentTime()) }

    private func load(refresh: Bool, at time: CMTime) {
        guard !stopped else { return }
        error = nil
        ready = false
        loading?.cancel()
        let request = request
        loading = Task {
            do {
                let source = try await request.resolve(refresh)
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
        let videoAsset = MediaVideoAsset(url, headers: request.headers)
        let item = AVPlayerItem(asset: videoAsset.asset)
        observation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.failed() }
        }
        player.replaceCurrentItem(with: item)
        self.videoAsset = videoAsset
        if time > .zero { await player.seek(to: time) }
        guard !Task.isCancelled else { return }
        ready = true
        MediaAudio.withSound()
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
        videoAsset = nil
        MediaAudio.done()
    }
}

struct VideoPlayerPage: View {
    let request: VideoRequest

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
                    if !model.ready {
                        // The cover the card showed, until the video plays.
                        if let cover = request.cover {
                            WeiboImage(url: cover, contentMode: .fit, placeholder: false)
                                .background(.black)
                                .ignoresSafeArea()
                        }
                        ProgressView().controlSize(.large).tint(.white)
                    }
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
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

/// The system's player, with its own controls and picture in picture.
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
