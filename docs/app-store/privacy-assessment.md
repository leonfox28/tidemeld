# App privacy and age-rating assessment

Checked 2026-11-06 against build 1.0.0 (3). This is a preparation record, not a published privacy label or a legal opinion.

## Sources and scope

- [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/): service-specific web views must be considered; on-device storage alone is not collection. Data must be classified by actual use, identity linkage and tracking.
- [Weibo privacy policy](https://weibo.com/signup/v5/privacy): covers its websites/H5, login, network logs, cookies, user activity, personalization and advertising. Do not transfer every permission of Weibo's native app to this client.
- [X privacy policy](https://x.com/en/privacy): covers account/contact information, cookies and identifiers, IP/log information, activity, personalization and advertising. Not every X feature is implemented by Tidemeld.
- [X adult-content policy](https://help.x.com/en/rules-and-policies/adult-content): permits labeled adult content and applies age-related restrictions. Tidemeld must preserve appropriate restrictions rather than assume the official app's rating applies.
- [Apple age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/): graphic sexual content and prolonged graphic/sadistic violence can make an app unrated. A higher age override is not a substitute for accurate questionnaire answers.

## Saved data-type draft

App Store Connect has an unpublished draft with these 12 data types. Purposes, identity linkage and tracking have not yet been finalized; the Publish button remains disabled.

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

The draft is intentionally incomplete. The maintainer has no analytics/backend, but the platforms' retained information must still be evaluated. Login/account requests are linked to identity; local feed merging does not remove that linkage. Platform-wide policy descriptions establish possible uses, not a complete endpoint-level map.

Before publishing, determine which data from these embedded services is combined with other-company data for targeted advertising/measurement. If tracking occurs, both the privacy label and the app's ATT behavior must agree. Build 3 has no AppTrackingTransparency request or explicit control over platform scripts. Do not publish a blanket “no tracking” answer based only on the absence of native advertising SDKs. Additional diagnostics or data categories must be added if the scoped web behavior establishes them.

## Age questionnaire

Known answers: UGC and social features, comments/replies, platform web navigation and Weibo advertising are present. The native client has no parental controls, age assurance or Declared Age Range integration. It is not a medical, gambling or contest app.

Outstanding: frequency and handling of mature/sexual/violent material from the selected feeds and platform pages. `parseXPost` in `ios/Tidemeld/Data/API/XWebAPI.swift` does not inspect `possibly_sensitive` or media sensitivity warnings before displaying available media. No lower rating or absence of graphic content has been asserted. The questionnaire is not saved. The full UGC report/block/filter work listed in `docs/APP_STORE.md` remains open.

## Content rights

The app accesses third-party content. Apple's content-rights field cannot truthfully be set to “does not contain/display/access third-party content.” Authorization to operate App Store Connect does not itself establish permission from Weibo/X or a lawful-use basis for US distribution. This factual basis is still requested from the maintainer; no rights declaration has been saved.
