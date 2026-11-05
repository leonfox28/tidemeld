# Review notes draft — not ready to submit

Resolve the release checklist in [APP_STORE.md](../APP_STORE.md) before using the text below. Add the tested content-reporting and blocking instructions after those features exist. Never put credentials, personal phone numbers or private contact emails in this repository.

---

maxbo is an independent, free, open-source Weibo client. It is not affiliated with or endorsed by Weibo. Its interface is in Simplified Chinese.

Authentication and network access:
- The app opens Weibo's official sign-in page in a system WebKit view. The native code does not inspect login form fields or passwords. After sign-in, it uses the resulting session cookies for direct requests to Weibo's web endpoints.
- The developer does not operate a server receiving Weibo credentials or content. The client does not claim to use an official OAuth integration or possess an authorization letter.
- Core functions require an existing Weibo account. Enter the dedicated review account in App Store Connect's separate sign-in fields. The account must remain usable throughout review; confirm that login does not depend on the developer receiving an SMS or approving a QR code.

Navigation:
- 首页: following feed. Tap a post to open its details, photos or video.
- 搜索: trending topics and post search.
- 通知: mentions, comments and likes.
- 我: current profile, settings and sign-out. Settings → 关于 maxbo → 隐私政策 opens the bundled policy without a network connection. The login screen also offers a policy button.

The app supports posting text/photos, commenting, replying, liking, reposting and deleting the signed-in user's own posts/comments. No purchases or subscriptions are offered.

The background audio mode supports user-started media playback, including Picture in Picture; it is not used for background feed fetching. The app does not periodically poll the service in the background.

Source code: https://github.com/leonfox28/maxbo
Support: https://github.com/leonfox28/maxbo/issues
