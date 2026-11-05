import SwiftUI

let privacyPolicyURL = URL(string: "https://github.com/leonfox28/maxbo/blob/main/docs/PRIVACY.md")!
let supportURL = URL(string: "https://github.com/leonfox28/maxbo/blob/main/docs/SUPPORT.md")!

/// The policy ships with the app, so it is readable before sign-in or offline.
struct PrivacyPage: View {
    @Environment(AppGraph.self) private var graph
    @State private var paragraphs: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if paragraph.hasPrefix("# ") {
                        Text(String(paragraph.dropFirst(2))).font(.title2.bold())
                    } else if paragraph.hasPrefix("## ") {
                        Text(String(paragraph.dropFirst(3))).font(.headline).padding(.top, 8)
                    } else {
                        Text((try? AttributedString(markdown: paragraph,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                            ?? AttributedString(paragraph))
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                Button("查看在线隐私政策", systemImage: "arrow.up.right.square") {
                    graph.openExternally(privacyPolicyURL)
                }
                Button("联系维护者", systemImage: "exclamationmark.bubble") {
                    graph.openExternally(issuesURL)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(AppTheme.foreground)
        .appBackground()
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let url = Bundle.main.url(forResource: "PRIVACY", withExtension: "md"),
                let text = try? String(contentsOf: url, encoding: .utf8) {
                paragraphs = text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
            } else {
                paragraphs = ["隐私政策暂时无法读取，请查看在线版本。"]
            }
        }
    }
}
