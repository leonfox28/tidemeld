# App privacy and age-rating assessment

Checked 2026-11-06. The build-3 questionnaire record below is historical and includes assumptions that were subsequently found insufficiently supported. It must not be treated as a verified endpoint-level assessment or an Apple review decision.

## Flare comparison and build 4 correction

The follow-up [public review research](flare-review-research.md) found Flare PR #1661 specifically named “Feature/appstore review,” including login agreement links, guest action visibility and moderation UI changes. It did not reveal Flare's private content-rights declaration or authorization materials. Some X/VVO reporting callbacks in tag 1.8.0 are empty; menu presence must not be mistaken for completed functionality.

The maintainer asked to follow Flare after reviewing its [US listing](https://apps.apple.com/us/app/flare-social-network-client/id6476077738) and [1.8.0 source](https://github.com/flaresocialapp/Flare/tree/1.8.0). The public listing is rated 16+ and discloses unlinked crash/performance diagnostics. It supports guest Mastodon browsing. Its X implementation uses web-cookie login, preserves `possibly_sensitive`, and defaults to concealing sensitive media. Its private review-account and content-rights answers are not public.

Tidemeld now independently implements platform-marked X media concealment and local literal keyword filters on both native platforms. No Flare code or new analytics SDK has been added. Sensitive media is not mounted or loaded until an individual reveal action; keywords cover author/body, quotes and comment previews, with settings persisted locally. Filters do not alter web content or platform settings, and are not a comprehensive classification of unmarked content.

The earlier reasoning “X permits some explicit material, therefore this app contains graphic sexual content and prolonged sadistic violence” was insufficient to establish the submitted frequency answers. The resulting Unrated value came from those answers, not from an Apple review. Reassessment must distinguish the intended general social client and actual controls from hypothetical content anywhere on a source platform. Similarly, applying four purposes and tracking to all eleven platform data types from broad platform policies was not an established data-flow audit. Flare's narrower label alone is not proof of the correct Tidemeld label; Tidemeld does not even have Flare's diagnostic collection.

Native audit: no maintainer backend, analytics/crash/advertising SDK, IDFA access, advertising measurement calls or cross-platform identity linkage was found. Platform account cookies and user actions go directly to their selected service; local keywords remain local. Separate consideration is still required for the official login, visitor-session, renewal and service-specific browser pages. Apple's [web-view guidance](https://developer.apple.com/app-store/app-privacy-details/) and [ATT FAQ](https://developer.apple.com/app-store/user-privacy-and-data-use/) explicitly include tracking inside functional web views, with an exception for open-web navigation. Absence of a native SDK alone does not resolve those pages' behavior. No “collects diagnostics” or blanket “collects nothing” answer should be copied from a competitor.

After the maintainer restored App Store Connect sign-in, processed build 4 was selected and its review notes were saved. The age questionnaire was corrected as described below. The published privacy label was inspected but not changed: the known native data flows do not resolve the remote scripts' actual advertising linkage. No claim of a completed privacy-label correction or a submitted review is warranted.

### Saved build 4 age correction

The questionnaire explicitly instructs developers to consider the experience with in-app controls enabled. For the general social client with default concealment of platform-marked sensitive X media, the two earlier speculative answers—graphic sexual content/nudity and prolonged graphic or sadistic violence—were changed from Infrequent to None. Other answers were retained, including UGC, social media, unrestricted web access, advertising, frequent mature themes and infrequent non-graphic sexual content. Apple calculated **16+** (17+ for older operating systems); the saved App Information page confirmed it. This is not an Apple content-review approval or a guarantee about every unmarked user post.

### Remaining privacy verification

The login page runs platform JavaScript, `prepareGuestCookies` loads the Weibo mobile site in nonpersistent WebKit storage, and `WebPageSessionRenewer` loads the Weibo site until session renewal completes. Temporary storage and stopping the page do not establish that no server-side collection or tracking occurred. Native code does not call Weibo's ad-impression monitor URLs. Local-only aggregation and keyword rules require no disclosure as collected data, but that does not determine the platform pages' purposes. Apple's functional-web-view and SSO guidance must be applied before replacing the existing broad label; neither a blanket tracking answer nor a blanket no-collection answer is verified by the present evidence.

The subsequent Add for Review attempt returned one required-field error: content-rights information. The app remains Preparing for Submission. Required-field validation is not an assessment of privacy correctness, UGC safeguards or reviewer access.

## Sources and scope

- [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/): service-specific web views must be considered; on-device storage alone is not collection. Data must be classified by actual use, identity linkage and tracking.
- [Weibo privacy policy](https://weibo.com/signup/v5/privacy): covers its websites/H5, login, network logs, cookies, user activity, personalization and advertising. Do not transfer every permission of Weibo's native app to this client.
- [X privacy policy](https://x.com/en/privacy): covers account/contact information, cookies and identifiers, IP/log information, activity, personalization and advertising. Not every X feature is implemented by Tidemeld.
- [X adult-content policy](https://help.x.com/en/rules-and-policies/adult-content): permits labeled adult content and applies age-related restrictions. Tidemeld must preserve appropriate restrictions rather than assume the official app's rating applies.
- [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/): graphic sexual content and prolonged graphic/sadistic violence can make an app unrated. A higher age override is not a substitute for accurate questionnaire answers.

## Historical published privacy label (still unchanged in App Store Connect)

App Store Connect now has a published label with these 12 data types. All purpose, identity-linkage and tracking questions were completed in the follow-up below; the UI confirmed publication by the account holder on 2026-11-06.

| Data | Relevant path / reason |
|---|---|
| Name, email, phone | Official platform account/login pages; contact information sent to the selected platform, not to the maintainer |
| Coarse location | Platforms can derive approximate location from network IP; no native location permission |
| Photos or videos | User-selected photo publishing/comment uploads to Weibo |
| Other user content | Post text, replies, comments, repost/quote text sent by the user |
| Browsing history | Platform-specific embedded pages and their logs |
| Search history | Weibo keyword search and platform web searches |
| User ID | Account/handle identifiers and authenticated requests |
| Device ID | Platform website/cookie identifiers; no native IDFA collection |
| Product interaction | Platform requests, likes/replies/reposts and web activity |
| Advertising data | Advertising within platform web pages, as covered by their policies |

The initial data-type draft was subsequently completed. The maintainer has no analytics/backend, but the platforms' retained information is included. Login/account requests are linked to identity; local feed merging does not remove that linkage. Platform-wide policy descriptions establish possible uses, not a complete endpoint-level map.

The published label includes platform data combination for targeted advertising/measurement. Both the privacy label and the app's ATT behavior must agree. Build 3 has no AppTrackingTransparency request or explicit control over platform scripts. Do not publish a blanket “no tracking” answer based only on the absence of native advertising SDKs. Additional diagnostics or data categories must be added if the scoped web behavior establishes them.

## Historical build 3 age questionnaire (superseded above)

Known answers: UGC and social features, comments/replies, platform web navigation and Weibo advertising are present. The native client has no parental controls, age assurance or Declared Age Range integration. It is not a medical, gambling or contest app.

The questionnaire was subsequently completed using a conservative assessment of the available social content, rather than claiming absent content without a filter. `parseXPost` in `ios/Tidemeld/Data/API/XWebAPI.swift` does not inspect `possibly_sensitive` or media sensitivity warnings before displaying available media. No absence of graphic content has been asserted. The questionnaire was saved; Apple calculated “Unrated” and explicitly said the app cannot be offered on the App Store with these answers. The full UGC report/block/filter work listed in `docs/APP_STORE.md` remains open.

## Content rights

The app accesses third-party content. Apple's content-rights field cannot truthfully be set to “does not contain/display/access third-party content.” Authorization to operate App Store Connect does not itself establish permission from Weibo/X or a lawful-use basis for US distribution. This factual basis is still requested from the maintainer; no rights declaration has been saved.

## Historical build 3 follow-up on 2026-11-06 (reasoning superseded above)

The maintainer explicitly asked the agent to complete the remaining fields. The privacy purpose assessment now uses the platforms' published practices as the basis for potential collection, including cases that depend on users' platform settings. X Privacy Policy §§1.2–1.3 and 2.1–2.3 explicitly cover account identity, activity/logs, advertising-partner data combination, personalization, advertising measurement, service analytics and security. This is sufficient to disclose these potential uses without assuming native SDKs are required.

For name, email, phone, coarse location, other user content, browsing/search history, user/device identifiers, product interaction and ad data: disclose App Functionality, Analytics, Product Personalization and Third-Party Advertising; linked to identity; used for tracking. This is an interpretation of the broad platform policy applied to the client's actual login/API/web paths. For photos uploaded by the native client to Weibo: App Functionality, linked to identity, not used for tracking; no X photo upload is implemented. A tracking label does not fix the absence of ATT behavior in build 3.

[Current X terms](https://x.com/en/tos), effective October 9, 2026, limit access to published interfaces and restrict scraping without express written permission except where applicable law requires otherwise. The repository uses web endpoints, not a documented OAuth/API integration. This source does not establish the application's content-rights basis; it makes a blanket assumption of permission inappropriate.

### Saved age answers

- No parental controls, age assurance or under-13 social-media restriction using Declared Age Range.
- Yes to unrestricted web access, UGC, social media, messaging/chat (comments/replies) and advertising.
- Infrequent profanity, horror, substance references and medical/treatment information; health/wellness topics present.
- Frequent mature/suggestive themes; infrequent sexual/nudity and graphic sexual/nudity content. The graphic category is included because X permits such material and the current parser does not enforce its sensitivity markers.
- Infrequent cartoon/fantasy, realistic, graphic/sadistic violence and weapons. With unrestricted platform content and no native content-safety enforcement, these categories have not been claimed absent.
- No simulated gambling, contests, real-money gambling or loot boxes as app functionality.

These are conservative category assessments, not empirical measurements of every user's personalized feed. Apple displayed “Unrated” for both current and pre-26 operating systems. Content filtering and safety enforcement need to be implemented and verified before revising these answers to describe a safer build; do not change answers solely to get past validation.

### Final submission validation

After publishing privacy answers and saving the age questionnaire, clicking “Add for Review” returned only one missing-field error: content-rights information must be set in App Information. No review submission was created. The absence of age/privacy errors in this required-field check does not override the age wizard's explicit “Unrated” warning or establish that build 3 meets tracking requirements.
