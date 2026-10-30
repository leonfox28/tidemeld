import Foundation
import Observation

/// How many pictures a post can have.
let maxDraftPictures = 9

/// A picture picked for a new post or comment, as a copy in the app's temporary
/// files; [pid] once uploaded.
struct DraftPicture: Sendable, Hashable, Identifiable {
    let id = UUID()
    let file: URL
    var pid: String? = nil
}

/// The post the user is writing.
struct ComposeDraft: Sendable, Hashable {
    var text = ""
    var pictures: [DraftPicture] = []
    var visibility: StatusVisibility = .public

    /// Weibo wants some text, pictures or not, as weibo.com's composer does.
    var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Copies the bytes of a picked picture to a temporary file, so a draft keeps
/// it without holding it in memory.
func storeDraftPicture(_ data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drafts")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent(UUID().uuidString)
    try data.write(to: file)
    return file
}

/// The draft of a new post. It outlives the compose page, so closing it loses
/// nothing, and starts over for another account.
@MainActor @Observable
final class ComposeDraftController {
    var draft = ComposeDraft()

    @ObservationIgnored private let api: WeiboAPI
    @ObservationIgnored private let openLists: OpenLists
    /// Bumped when the draft starts over, so a send for the last account
    /// changes nothing.
    @ObservationIgnored private var generation = 0

    init(api: WeiboAPI, openLists: OpenLists, session: SessionController) {
        self.api = api
        self.openLists = openLists
        session.onUidChange { [weak self] _ in
            guard let self else { return }
            generation += 1
            draft = ComposeDraft()
        }
    }

    /// Adds [files], as many as fit, and returns how many were left out.
    @discardableResult
    func addPictures(_ files: [URL]) -> Int {
        let room = maxDraftPictures - draft.pictures.count
        draft.pictures += files.prefix(max(0, room)).map { DraftPicture(file: $0) }
        return max(0, files.count - room)
    }

    func removePicture(_ id: UUID) {
        draft.pictures.removeAll { $0.id == id }
    }

    /// Uploads the pictures not yet uploaded, one at a time, then posts the
    /// draft and clears it. [onUpload] hears which picture (from 0) goes up.
    ///
    /// The new status goes atop the open lists that show the user's posts.
    /// Throws on failure; the pictures uploaded by then keep their pids, so
    /// sending again doesn't upload them again.
    func send(onUpload: (Int) -> Void = { _ in }) async throws {
        let generation = generation
        var pids: [String] = []
        for (i, picture) in draft.pictures.enumerated() {
            if let pid = picture.pid {
                pids.append(pid)
                continue
            }
            onUpload(i)
            let data: Data
            do {
                data = try Data(contentsOf: picture.file)
            } catch {
                throw WeiboError.api("读取图片失败")
            }
            let pid = try await api.uploadPicture(data)
            guard generation == self.generation else { return }
            if let index = draft.pictures.firstIndex(where: { $0.id == picture.id }) {
                draft.pictures[index].pid = pid
            }
            pids.append(pid)
        }
        let status = try await api.postStatus(
            draft.text.trimmingCharacters(in: .whitespacesAndNewlines), pids: pids,
            visibility: draft.visibility)
        guard generation == self.generation else { return }
        draft = ComposeDraft()
        if let status { openLists.prependOwn(status) }
    }
}

/// What the user is writing to repost, by status id. It stays until sent, so
/// closing the sheet loses nothing, and starts over for another account.
@MainActor
final class RepostDrafts {
    private var drafts: [String: String] = [:]

    init(session: SessionController) {
        session.onUidChange { [weak self] _ in self?.drafts = [:] }
    }

    subscript(id: String) -> String? {
        get { drafts[id] }
        set { drafts[id] = newValue }
    }
}
