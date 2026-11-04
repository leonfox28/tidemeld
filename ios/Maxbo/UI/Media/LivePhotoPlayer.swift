import AVFoundation
import Observation
import SwiftUI

/// Plays the moving part of the viewer's live photos ("实况"), one at a time
/// and once through, over the still picture; its video is fetched only when
/// asked for, or when the viewer plays it on its own ([autoplay]). Its URL
/// expires like a video's (PLAN §8), so one that fails is fetched afresh from
/// status [statusId], once.
@MainActor @Observable
final class LivePhotoPlayer {
    /// The picture whose motion is loading or playing.
    private(set) var current: PicInfo?
    /// Whether [current] is moving, rather than still loading.
    private(set) var moving = false
    /// The id of the picture whose motion failed to load.
    private(set) var failed: String?

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let api: WeiboAPI
    @ObservationIgnored private let statusId: String?
    /// The picture [player] holds the motion of, kept buffered for playing
    /// again.
    @ObservationIgnored private var loaded: String?
    /// Whether [loaded]'s URL came from fetching its status again.
    @ObservationIgnored private var fetched = false
    @ObservationIgnored private var muted = false
    /// The ids of the pictures that have played on their own.
    @ObservationIgnored private var autoplayed: Set<String> = []
    @ObservationIgnored private var resolving: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    @ObservationIgnored private var released = false

    init(api: WeiboAPI, statusId: String?) {
        self.api = api
        self.statusId = statusId
        player.actionAtItemEnd = .pause
        rateObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in
                guard let self else { return }
                self.moving = playing && self.current != nil
            }
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
            ) { [weak self] note in
                let item = ObjectIdentifier(note.object as AnyObject)
                MainActor.assumeIsolated {
                    guard let self, let current = self.player.currentItem, ObjectIdentifier(current) == item
                    else { return }
                    withAnimation(.easeOut(duration: 0.3)) { self.current = nil }
                }
            })
    }

    /// Plays [pic]'s motion from the start, with sound unless [muted]; with
    /// [refresh], from a URL fetched afresh.
    func play(_ pic: PicInfo, refresh: Bool = false, muted: Bool = false) {
        guard !released else { return }
        stop()
        current = pic
        failed = nil
        self.muted = muted
        player.isMuted = muted
        if muted { MediaAudio.muted() } else { MediaAudio.withSound() }
        if pic.id == loaded, !refresh, player.currentItem?.status == .readyToPlay {
            player.seek(to: .zero)
            player.play()
            return
        }
        loaded = nil
        resolving = Task {
            let source: VideoSource
            do {
                source = try await resolveLivePhotoURL(api, pic: pic, statusId: statusId, refresh: refresh)
            } catch {
                if Task.isCancelled { return }
                devLog("live photo: \(WeiboError.of(error))")
                current = nil
                failed = pic.id
                return
            }
            guard !Task.isCancelled, let url = URL(string: source.url) else { return }
            loaded = pic.id
            fetched = source.fetched
            start(pic, from: url)
        }
    }

    private func start(_ pic: PicInfo, from url: URL) {
        let item = AVPlayerItem(asset: weiboVideoAsset(url))
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.itemFailed(pic) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func itemFailed(_ pic: PicInfo) {
        guard !released else { return }
        devLog("live photo failed")
        // Nothing to play again: the next play loads it anew.
        loaded = nil
        guard current?.id == pic.id else { return }
        if fetched || statusId == nil {
            current = nil
            failed = pic.id
        } else {
            play(pic, refresh: true, muted: muted)
        }
    }

    /// Plays [pic]'s motion without sound, as the viewer does on its own, which
    /// it does once for each picture: one swiped back to stays still, and costs
    /// no new download.
    func autoplay(_ pic: PicInfo) {
        if autoplayed.insert(pic.id).inserted { play(pic, muted: true) }
    }

    func stop() {
        resolving?.cancel()
        player.pause()
        current = nil
        moving = false
    }

    /// Lets go of the motion as the viewer closes; nothing plays after.
    func release() {
        released = true
        stop()
        statusObservation = nil
        player.replaceCurrentItem(with: nil)
        MediaAudio.done()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}

/// A player's picture, filling its frame as the still under it does.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
