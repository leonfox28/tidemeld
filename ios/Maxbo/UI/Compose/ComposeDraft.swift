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

/// Where picked pictures are kept while their drafts last; drafts don't
/// outlive the app, so it is emptied as the app starts.
let draftPicturesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("drafts")

/// Copies the bytes of a picked picture to a temporary file, so a draft keeps
/// it without holding it in memory.
func storeDraftPicture(_ data: Data) throws -> URL {
    try FileManager.default.createDirectory(at: draftPicturesDirectory, withIntermediateDirectories: true)
    let file = draftPicturesDirectory.appendingPathComponent(UUID().uuidString)
    try data.write(to: file)
    return file
}

/// The bytes of [picture], to upload.
func readDraftPicture(_ picture: DraftPicture) throws(WeiboError) -> Data {
    do {
        return try Data(contentsOf: picture.file)
    } catch {
        throw .api("图片读取失败")
    }
}

/// Deletes the files of pictures no draft holds any more.
func discardDraftPictures(_ pictures: [DraftPicture]) {
    for picture in pictures { try? FileManager.default.removeItem(at: picture.file) }
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
            discardDraftPictures(draft.pictures)
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
        discardDraftPictures(draft.pictures.filter { $0.id == id })
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
            let pid = try await api.uploadPicture(try readDraftPicture(picture))
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
        discardDraftPictures(draft.pictures)
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
