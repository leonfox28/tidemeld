import SwiftUI

struct ProfileCount {
    let label: String
    let value: Int64
}
struct ProfilePresentation {
    var name: String?
    var avatarURL: String?
    var coverURL: String?
    var counts: [ProfileCount] = []
    var relation: String?
    var verification: String?
    var description: String?
    var loading = false
    var failure: String?
}

struct SocialProfileHeader<Badge: View, Details: View>: View {
    let profile: ProfilePresentation
    let onRetry: () -> Void
    var actions: ProfileActions? = nil
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let details: () -> Details
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover = profile.coverURL {
                WeiboImage(url: cover, maxPixels: 1200).frame(height: 120).frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    PostAvatar(url: profile.avatarURL, label: profile.name ?? "头像", size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(profile.name ?? " ").font(.title3.weight(.semibold)).lineLimit(1)
                                .redacted(reason: profile.name == nil && profile.loading ? .placeholder : [])
                            badge()
                            if actions == nil, let relation = profile.relation { TagLabel(text: relation) }
                        }
                        if actions == nil {
                            counts
                        } else if let relation = profile.relation {
                            TagLabel(text: relation)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let actions { SocialProfileActions(actions: actions) }
                }
                if actions != nil { counts }
                if let verification = profile.verification {
                    Text(verification).font(.caption).foregroundStyle(AppTheme.secondary)
                }
                if let description = profile.description { Text(description).font(.subheadline) }
                details()
                if let failure = profile.failure {
                    HStack {
                        Text(failure).font(.caption).foregroundStyle(AppTheme.error)
                        Spacer()
                        Button("重试", action: onRetry).font(.caption)
                    }
                }
            }.foregroundStyle(AppTheme.foreground).padding(16)
            Divider().overlay(AppTheme.outline)
        }
    }
    private var counts: some View {
        HStack(spacing: 16) {
            ForEach(profile.counts.indices, id: \.self) { index in
                let count = profile.counts[index]
                Text(
                    "\(Text(formatCount(count.value)).fontWeight(.semibold).foregroundStyle(AppTheme.foreground)) \(count.label)"
                )
                .foregroundStyle(AppTheme.secondary)
            }
        }.font(.subheadline).redacted(reason: profile.loading ? .placeholder : [])
    }

}
