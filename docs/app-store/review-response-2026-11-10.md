# Response to the November 9 review

Sent to App Review on 2026-11-10 at 11:11 Asia/Shanghai for submission `89a7b8ad-e7bc-4e0d-8ad2-53f943a2a37e`, after build 1.0.0 (10) was uploaded, distributed internally and selected for review. The message appeared in App Store Connect; the subsequent resubmission entered Waiting for Review. See [APP_STORE.md](../APP_STORE.md).

---

Hello App Review,

Thank you for reviewing Tidemeld. We have prepared build 1.0.0 (10) and addressed the three items:

Guideline 2.3.8: The installed app display name is now Tidemeld, matching the English (US) App Store name.

Guideline 4.8: We respectfully request reconsideration under the exception for clients of specific third-party services that require direct sign-in to access the user's content. Tidemeld has no proprietary user account or separate primary-account login. It is a client for Weibo and X: each official website login authorizes only the corresponding platform account, personal feed and actions. These are not alternative sign-in providers for a Tidemeld account. Sign in with Apple would not authenticate the user's existing Weibo or X account. Public Weibo browsing is also available without sign-in, subject to the platform's guest limits.

Guideline 5.1.2(i): The previous privacy questionnaire was overly broad and did not accurately describe the native implementation. We have corrected the published App Privacy answers to four data types: Photos or Videos, Other User Content, Search History and User ID. They are declared for App Functionality, linked to the user's platform account and not used for tracking. Tidemeld has no advertising or analytics SDK, IDFA access, developer telemetry or developer-operated backend. User-selected uploads, text, searches and authenticated requests go directly to the selected platform. Platform webpages use their own cookies and policies, which our privacy policy describes; we do not claim to control all remote platform processing.

The new build also includes image-viewer transition and feed-pagination fixes. Updated review notes describe guest access, account access and current functionality. Please let us know if further information is needed for the 4.8 exception or privacy review.

Thank you.
