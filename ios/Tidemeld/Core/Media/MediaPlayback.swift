import Foundation

/// Platform adapters supply content and refresh behavior; players own only playback state.
struct VideoRequest: Identifiable {
    let id = UUID()
    let cover: String?
    let headers: [String: String]
    let resolve: @MainActor (Bool) async throws -> VideoSource
}

struct PhotoMotion {
    let headers: [String: String]
    let canRefresh: Bool
    let resolve: @MainActor (PicInfo, Bool) async throws -> VideoSource
}
