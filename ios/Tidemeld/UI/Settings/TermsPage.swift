import SwiftUI

enum ContentTerms {
    static let version = "2026-11-12"
    static var text: String? {
        Bundle.main.url(forResource: "TERMS", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

struct TermsPage: View {
    var accept: (() -> Void)? = nil
    @State private var showingPrivacy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let text = ContentTerms.text {
                    ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph.replacingOccurrences(of: "^#{1,2} ", with: "", options: .regularExpression))
                            .font(paragraph.hasPrefix("#") ? .headline : .body)
                    }
                    Button("隐私政策") { showingPrivacy = true }
                    if let accept {
                        Button("同意并继续", action: accept)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        Text("点击“同意并继续”表示你接受以上条款。如不同意，请停止使用叠澜。")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                } else {
                    Text("使用条款暂时无法读取，请重新打开应用。")
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("使用条款")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPrivacy) { NavigationStack { PrivacyPage() } }
    }
}
