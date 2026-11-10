# Review notes — version 1.0.0 (10)

Saved to App Store Connect on 2026-11-10 for build 10 after the build-4 rejection. Build 10 entered Waiting for Review at 11:11 Asia/Shanghai. Actual upload/review status is recorded in [APP_STORE.md](../APP_STORE.md). Contact details remain only in App Store Connect. The maintainer continues to submit without test credentials; guest access does not cover authenticated functions and has not been accepted by Apple as a substitute.

---

Tidemeld is an independent, free, open-source client for Weibo and X on iPhone and iPad. It combines their following feeds locally. It is not affiliated with either service. The interface is in Simplified Chinese.

Response to the November 9 review:
- 2.3.8: Build 10 changes the installed display name to Tidemeld, matching the English (US) store name.
- 4.8: We request reconsideration under the exception for clients of specific third-party services requiring users to sign in directly to those services. Tidemeld does not create or authenticate a Tidemeld account. Weibo and X sign-in only authorize access to the respective service's existing account, feeds and actions. They are not alternative identity providers for a separate primary account. Sign in with Apple would not grant access to those platform accounts.
- 5.1.2(i): We corrected the overly broad App Privacy answers. The published answers identify Photos or Videos, Other User Content, Search History and User ID for App Functionality, linked to the platform account, not used for tracking. The native app has no advertising/analytics SDK, IDFA access, developer telemetry or developer-operated backend. Content and authenticated requests go directly to the selected service. Official platform webpages use their own cookies and policies, as described in our privacy policy; we do not claim to control all of their remote processing.

Review access:
- No test credentials are provided. Please start with guest browsing: launch the app to see a native public Weibo feed; refresh, open a post, and view its media. Weibo limits the guest feed to its first page. Search shows trending topics and links to limited public web results.
- Personal feeds and account actions require an existing platform account. There is no built-in demo mode. Each service may require SMS or security verification, which this client cannot bypass. Please let us know if additional review access is needed.
- To sign in, tap the person icon at the top left of 首页 (Home), then 添加账号 (Add Account), then Weibo or X. The official service website opens in WebKit. Native code does not read password or verification-code fields. Session cookies are stored per account in the device Keychain; requests go directly to platform web endpoints. This is not an official OAuth integration.

Navigation and features:
- Home's title menu selects 聚合 (All), 微博 or X. Multiple accounts are merged, sorted and deduplicated locally; actions remain bound to the originating account.
- Native post details, comments, profiles and shared image/video viewers support both services. Weibo supports search, notifications, likes, comments, reposts and text/photo publishing. X supports replies, likes, reposts and quotes; native X search, notifications and standalone new-post publishing are not implemented. Platform endpoint changes can affect availability.
- 设置 (Settings) includes appearance, text size, image preferences and 关于叠澜 (About) → 隐私政策 (Privacy Policy), available offline. Remove local sessions in 账号管理 (Accounts); this does not delete the platform account.
- Platform-marked sensitive X media is hidden and not loaded by default, with per-item reveal/hide controls. 设置 → 内容过滤 manages local literal keyword filters for native content. These filters do not alter webpages or classify every unmarked item.
- Store screenshots use clearly labeled original sample data injected by offline tests. Those samples are not an in-app demo mode.
- No purchases or subscriptions. Background audio supports user-started media playback/Picture in Picture, not feed polling.

Build 10 also includes image-viewer transition and aggregated-feed pagination fixes.
Source: https://github.com/leonfox28/tidemeld
Support: https://github.com/leonfox28/tidemeld/issues
