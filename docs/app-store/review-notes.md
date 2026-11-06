# Review notes — version 1.0.0 (4)

The text below was saved to App Store Connect for build 4 on 2026-11-06 after the maintainer restored sign-in. The maintainer chose to submit without test-account credentials and supplied review contact details directly for App Store Connect. Do not put those contact details or any credentials in this repository. Apple has not approved guest-only review access; guest browsing is not a substitute for authenticated review access. Build 1.0.0 (4) was submitted on 2026-11-06 at 09:45 Asia/Shanghai and is Waiting for Review, submission ID `89a7b8ad-e7bc-4e0d-8ad2-53f943a2a37e`. The follow-up items in [APP_STORE.md](../APP_STORE.md) remain open.

---

Tidemeld is an independent, free, open-source social feed aggregator for iPhone and iPad. It combines Weibo and X following feeds locally on the user's device. It is not affiliated with or endorsed by either platform. The interface is in Simplified Chinese.

Review access for this submission:
- No test credentials are provided. Please begin with guest browsing below. It does not cover personal feeds or account actions; we can respond if further access is required.

Authentication and access:
- Tap the person icon at the top left of 首页 (Home) to open 账号管理 (Accounts), then 添加账号 (Add Account), and select Weibo or X.
- Sign-in opens the selected platform's official website in a WebKit view. Native code does not read passwords, verification codes or login form fields. The client stores session cookies per account in the device Keychain and makes direct requests to the platform's web endpoints.
- We do not operate a backend receiving platform credentials or content. This is not an official OAuth integration.
- Personal following feeds and interactions require a platform account. Each platform may require SMS or other security verification, which Tidemeld cannot disable. The app does not include a built-in demo mode.

Navigation and aggregation:
- 首页 (Home): after sign-in, use the title menu to choose 聚合 (All), 微博 (Weibo) or X. All combines every signed-in account; each platform filter combines accounts on that platform. Merging, chronological sorting and same-platform deduplication happen locally. Posts display a platform icon and actions use the originating account.
- Without sign-in, Home shows some public Weibo posts as native cards with refresh and media viewing. Weibo currently limits this guest feed to its first page. This does not provide access to personal following feeds or account actions.
- Open a post to read details and comments. Images and videos use shared native viewers. X replies can display available parent posts above the current post.
- 搜索 (Search): Weibo trending topics and, after Weibo sign-in, native keyword search. Guests can open limited public Weibo web results. Further browsing may require login.
- 通知 (Notifications): Weibo comments, mentions and likes, available with a Weibo account.
- 设置 (Settings): appearance, text size, image preferences and app information. 设置 → 关于叠澜 → 隐私政策 opens the bundled policy offline. Accounts can be removed individually in 账号管理; removing a local session does not delete the platform account.

Store screenshots:
- Screenshots show real views with labeled, original samples injected by an offline test, not a built-in demo mode.

Content controls:
- X media marked sensitive by the platform is hidden and not loaded by default in feeds, quoted posts and comments. A user can reveal an individual item and hide it again.
- 设置 → 内容过滤 (Settings → Content Filtering) manages literal local keywords. Matching native posts/comments, including quoted text and reply previews, are collapsed. Rules stay on-device, do not affect webpages or platform settings, and do not classify every unmarked item.

Other functionality:
- Weibo includes likes, comments, replies, reposts, text/photo publishing and deletion of the user's own posts/comments.
- X includes reply, like, repost and quote controls. Native X search, notifications, profile pages and standalone new-post publishing are not implemented. X @ mentions and topics open platform web pages. X integration remains limited and platform endpoint changes can affect availability.
- These account actions are part of the submitted build; the app is not a read-only viewer. There are no hidden reviewer-only features. No purchases or subscriptions are offered.
- The background audio mode supports user-started media playback, including Picture in Picture. It is not used for background feed fetching or polling.

Source code: https://github.com/leonfox28/tidemeld
Support: https://github.com/leonfox28/tidemeld/issues
