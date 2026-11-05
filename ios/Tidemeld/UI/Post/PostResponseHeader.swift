import SwiftUI

struct PostResponseTab: Identifiable {
    let id: String
    let label: String
    let count: Int
}

/// Providers expose available response lists and an optional order control.
struct PostResponseHeader<Order: View>: View {
    let tabs: [PostResponseTab]
    let selected: String
    let likes: Int
    let select: (String) -> Void
    @ViewBuilder let order: () -> Order
    var body: some View {
        HStack(spacing: 12) {
            if tabs.count > 1 {
                Picker("列表", selection: Binding(get: { selected }, set: select)) {
                    ForEach(tabs) { tab in
                        Text("\(tab.label) \(formatCount(tab.count))").tag(tab.id)
                    }
                }.pickerStyle(.segmented).fixedSize()
            } else if let tab = tabs.first {
                Text("\(tab.label) \(formatCount(tab.count))").font(.subheadline.weight(.semibold))
            }
            order()
            Spacer()
            Text("赞 \(formatCount(likes))").font(.footnote).foregroundStyle(AppTheme.secondary)
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }
}
