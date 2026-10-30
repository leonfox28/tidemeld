import SwiftUI

/// Debug builds only: checks the app's reading of the real API, opens pages by
/// path, and tries session renewal. Logs counts and shapes, never values.
struct DiagnosticsPage: View {
    @Environment(AppGraph.self) private var graph
    @State private var lines: [String] = []
    @State private var running = false
    @State private var path = ""

    var body: some View {
        List {
            Section {
                Button("核对接口（只读）") { run { await probeReads($0) } }
                Button("模拟登录过期") { run { await probeRenewal($0) } }
            }
            .disabled(running)
            .listRowBackground(AppTheme.surface)
            Section("打开页面") {
                TextField("status/id、u/uid、n/昵称、results/词", text: $path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        #if DEBUG
                        DebugLaunch.open(path.trimmingCharacters(in: .whitespaces), graph)
                        #endif
                    }
            }
            .listRowBackground(AppTheme.surface)
            if !lines.isEmpty {
                Section("记录") {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .appListStyle()
        .navigationTitle("开发者诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run(_ probe: @escaping @MainActor (@escaping @MainActor (String) -> Void) async -> Void) {
        running = true
        lines = []
        Task { @MainActor in
            await probe { line in
                lines.append(line)
                devLog("diag: \(line)")
            }
            running = false
        }
    }

    /// Reads through the app's own API what its pages read: the account, the
    /// timeline, a status and its comments, the profile, hot and searched
    /// posts, and which notices are unread (the notice lists themselves would
    /// mark them read). Logs counts only.
    private func probeReads(_ log: @escaping @MainActor (String) -> Void) async {
        guard let uid = graph.session.state.uid else {
            log("reads need a signed-in session")
            return
        }
        let api = graph.api.withoutRenewal()
        func step(_ label: String, _ read: () async throws -> String) async {
            do {
                log("\(label): \(try await read())")
            } catch {
                log("\(label): \(WeiboError.of(error).message)")
            }
        }
        for site in WeiboCookieJar.sites {
            log("jar \(site): \(graph.session.jar.names(site).joined(separator: ", "))")
        }
        await step("account") { try await api.fetchCurrentAccount().uid == uid ? "the signed-in one" : "another" }
        var first: Status?
        await step("timeline") {
            let page = try await api.fetchHomeTimeline(uid: uid)
            first = page.items.first
            let statuses = page.items
            let pics = statuses.flatMap { [$0] + ($0.retweeted.map { [$0] } ?? []) }.flatMap { $0.pics + $0.mixedPics }
            return "\(statuses.count) statuses (\(statuses.filter { !$0.pics.isEmpty }.count) with pictures, "
                + "\(statuses.filter { $0.video != nil }.count) videos, "
                + "\(pics.filter { $0.liveVideo != nil }.count) live photos, "
                + "\(statuses.filter { $0.retweeted != nil }.count) reposts), more=\(page.nextCursor != nil)"
        }
        if let status = first {
            await step("status") {
                let full = try await api.fetchStatus(status.id)
                return "full text=\(full.plainText != nil), \(full.commentsCount) comments counted"
            }
            if let author = status.user?.id {
                await step("comments") {
                    let page = try await api.fetchComments(statusId: status.id, authorId: author, order: .hot)
                    return "\(page.items.count), more=\(page.nextCursor != nil)"
                }
            }
        }
        await step("profile") { try await api.fetchProfile(uid: uid).user.id == uid ? "found" : "another user" }
        await step("own statuses") { "\(try await api.fetchUserStatuses(uid: uid).items.count)" }
        await step("hot search") {
            let hot = try await api.fetchHotSearch()
            return "\(hot.pinned.count) pinned, \(hot.items.count) ranked"
        }
        await step("search") {
            let results = try await api.searchStatuses("微博")
            return "\(results.statuses.items.count), topic=\(results.topic != nil)"
        }
        await step("unread") {
            let kinds = try await api.fetchUnreadNotices().kinds.map(\.label).sorted()
            return kinds.isEmpty ? "none" : kinds.joined(separator: ", ")
        }
    }

    /// Swaps the session's `SUB` for an invalid one, then loads the timeline
    /// through the app's own API, to see whether renewal works and how long it
    /// takes. Logs which `SUB` ends up where, never values. If the session
    /// ends, signs back in with the cookies from before, as long as they still
    /// work.
    private func probeRenewal(_ log: @escaping @MainActor (String) -> Void) async {
        let session = graph.session
        guard let uid = session.state.uid else {
            log("renewal probe needs a signed-in session")
            return
        }
        let lapsed = "lapsed-by-diagnostics"
        let jar = session.jar
        let saved = jar.toCookies()
        let savedSub = saved[WeiboCookieJar.web]?["SUB"]
        func compare(_ sub: String?) -> String {
            switch sub {
            case nil: "missing"
            case lapsed: "the lapsed one"
            case savedSub: "as before"
            default: "new"
            }
        }
        let webBefore = await graph.webCookies.readWeiboCookies()[WeiboCookieJar.web]?["SUB"]
        log("webview SUB: \(compare(webBefore))")
        var lapsedCookies = saved
        lapsedCookies[WeiboCookieJar.web, default: [:]]["SUB"] = lapsed
        jar.replaceAll(lapsedCookies)
        let started = ContinuousClock.now
        do {
            let page = try await graph.api.fetchHomeTimeline(uid: uid)
            log("timeline: \(page.items.count) statuses after \(ContinuousClock.now - started)")
        } catch {
            log("timeline: \(WeiboError.of(error).message) after \(ContinuousClock.now - started)")
        }
        let sessionSub = jar.value(WeiboCookieJar.web, "SUB")
        let webAfter = await graph.webCookies.readWeiboCookies()[WeiboCookieJar.web]?["SUB"]
        log("session SUB: \(compare(sessionSub))")
        log(
            "webview SUB: \(compare(webAfter))\(webAfter == webBefore ? " (unchanged)" : " (changed)")"
                + (webAfter == sessionSub ? ", same as the session" : ""))
        if session.state.uid == nil {
            log("signed out: signing back in with the cookies from before")
            do {
                try await session.completeLogin(saved)
                log("signed back in")
            } catch {
                log("signing back in: \(WeiboError.of(error).message)")
            }
        } else if sessionSub == lapsed {
            jar.replaceAll(saved)
            log("not renewed: put the session back")
        }
    }
}
