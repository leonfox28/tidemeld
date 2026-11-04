import AVFoundation

/// How the app's videos and live photos sound alongside other apps.
///
/// With sound, they play as a video app's do: through the silent switch, in
/// picture in picture, pausing other apps' audio while they play. Live photos
/// moving on their own are muted, and leave other apps' audio alone.
enum MediaAudio {
    static func withSound() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    static func muted() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    /// Once nothing plays: other apps' audio carries on.
    static func done() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
