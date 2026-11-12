# Flare public App Store review research

Checked 2026-11-06 at the maintainer's request. This is a public-evidence comparison, not a record of Flare's private App Store Connect answers or a legal conclusion about either app.

## Search scope

- Read the repository snapshot `e23af9885cda97ede43399815ac00862695db62e` and checked relevant code against release tag `1.8.0` (`89f115c42e271ef3a58f61ff4af515da8bd6dcc6`).
- Retrieved 2,764 public issue/PR records and searched their titles/bodies; used targeted GitHub searches including comments for App Store/appstore, copyright, review, 5.2.2 and Chinese equivalents. This is not a claim to have manually read every comment in the repository.
- Inspected all nine public Discussions and their returned comments, the review-related PR's commits/files/comments/review, the official website and US App Store listing, and web search results including the author's V2EX introduction.
- Excluded unrelated products also named Flare, including flare.link, flare.co and other social/video services. Did not contact the author or post an issue.

## Direct evidence of review preparation

[PR #1661, “Feature/appstore review”](https://github.com/flaresocialapp/Flare/pull/1661) was opened by Tlaster on 2025-12-22 and merged on 2025-12-24. It contains 14 commits and 125 changed files. Its body is empty, there are no ordinary PR comments or inline review comments, and the returned review is a Copilot code review, not correspondence from Apple.

Relevant changes:

| Change | Public evidence | What it establishes |
|---|---|---|
| Login agreement link | [add EULA](https://github.com/flaresocialapp/Flare/commit/77e5fcaca064ba2dbc84c136e77feb7889861595) | Adds a login-agreement caption linking to Bluesky terms, X rules or a server's `/about` page; the VVO branch is excluded. It does not add a platform authorization letter or a content-rights attestation. |
| Guest-visible post actions | [make post actions visible in guest mode](https://github.com/flaresocialapp/Flare/commit/9b512af5129185931d88d25c3fd6dd5806da9f18) | Changes Mastodon action visibility. Several callbacks still depend on a signed-in account; visible controls do not establish that guests can complete every action. |
| Report confirmation | [add alert dialog for profile report](https://github.com/flaresocialapp/Flare/commit/2b050106e73ccf3e06327f686130736ca4631fe0) | Adds an iOS confirmation dialog before invoking profile reporting. |
| Mute/block post actions | [add mute and block to post](https://github.com/flaresocialapp/Flare/commit/d1308930a64bff1e455a77ff486f05b498227379) | Adds post-level access to account-dependent moderation actions. |

The [US listing](https://apps.apple.com/us/app/flare-social-network-client/id6476077738) shows 1.0.0 on 2025-12-28, shortly after this PR. The timing is consistent with release preparation, but no public Apple response identifies which changes caused approval.

## Current implementation and disclosures

- X uses [WebCookie login](https://github.com/flaresocialapp/Flare/blob/1.8.0/social/xqt/src/commonMain/kotlin/dev/dimension/flare/ui/presenter/login/XQTLoginProvider.kt#L29), opening the official login flow. Its agreement URL points to X rules. [VVO login](https://github.com/flaresocialapp/Flare/blob/1.8.0/social/vvo/src/commonMain/kotlin/dev/dimension/flare/ui/presenter/login/VVOLoginProvider.kt#L25) also uses WebCookie and returns no separate agreement URL. Neither code path proves the presence or absence of a private licensing agreement.
- X block/mute actions call platform operations through [XQTLoader](https://github.com/flaresocialapp/Flare/blob/1.8.0/social/xqt/src/commonMain/kotlin/dev/dimension/flare/data/datasource/xqt/XQTLoader.kt). This is stronger evidence of actual implementation than a menu label alone.
- In tag 1.8.0 the post Report item uses `ClickEvent.Noop` in both [XQT.kt](https://github.com/flaresocialapp/Flare/blob/1.8.0/social/xqt/src/commonMain/kotlin/dev/dimension/flare/ui/model/mapper/XQT.kt#L900) and [VVO.kt](https://github.com/flaresocialapp/Flare/blob/1.8.0/social/vvo/src/commonMain/kotlin/dev/dimension/flare/ui/model/mapper/VVO.kt#L299). The shared [click handler](https://github.com/flaresocialapp/Flare/blob/1.8.0/shared/src/commonMain/kotlin/dev/dimension/flare/ui/model/ClickContext.kt#L84) maps Noop to an empty callback. Do not describe these source paths as complete reporting implementations. Source inspection is not verification that the distributed binary exactly matches the tag.
- The App Store listing openly markets X alongside Mastodon, Bluesky, Misskey and Nostr, describes guest Mastodon browsing, and shows 16+ plus unlinked crash/performance diagnostics. Those public disclosures do not reveal its content-rights answer, review credentials or supplied supporting documents.
- The listing and About screen link to [Mask Network legal documents](https://legal.mask.io/maskbook/). The linked iOS privacy policy concerns Mask Network and dates to 2020; it is not a Flare-specific record of permission from Weibo or X.
- In the [author's 2024 V2EX introduction](https://www.v2ex.com/t/1013380), Tlaster describes adding X and planning Weibo. The post and its three replies do not explain copyright declarations or Apple approval materials.

## What remains unknown

No platform authorization letter, actual content-rights questionnaire answer, App Review correspondence or legal-use analysis for Flare was found in the inspected public sources. This means the information was not found, not that no such document or permission exists. The AGPL license covers the source code; it does not disclose rights to third-party social posts.

The confirmed implementation lessons are platform-rule links, default content controls, guest-visible navigation, and real account-dependent mute/block/report flows where supported. None of these automatically answers Tidemeld's content-rights declaration. Do not copy empty reporting actions or describe a competitor's public listing as evidence of our rights.

## 2026-11-12 source recheck

Master commit `88fb5d9a65364f42e926393024d4db81ea972f7b` still uses `ClickEvent.Noop` for the [X report item](https://github.com/flaresocialapp/Flare/blob/88fb5d9a65364f42e926393024d4db81ea972f7b/social/xqt/src/commonMain/kotlin/dev/dimension/flare/ui/model/mapper/XQT.kt#L906) and the [Weibo report item](https://github.com/flaresocialapp/Flare/blob/88fb5d9a65364f42e926393024d4db81ea972f7b/social/vvo/src/commonMain/kotlin/dev/dimension/flare/ui/model/mapper/VVO.kt#L305). The shared click handler maps it to an empty callback. X has a block endpoint implementation; Weibo's loader declares blocking unsupported. These source observations do not establish what Apple accepted or whether the store binary behaves identically. Tidemeld independently connects real platform report pages and confirmed block actions.
