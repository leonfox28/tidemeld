# Store screenshots

Generated 2026-11-06 from the real SwiftUI views in `ios/TidemeldTests/StoreScreenshotTests.swift`. Each platform has four PNGs: combined feed, X with dark appearance, account management and text-size settings.

| Device | Dimensions | Local output |
|---|---|---|
| iPhone | 1206 × 2622 | `ios/build/app-store/screenshots/iphone/` |
| iPad | 2064 × 2752 | `ios/build/app-store/screenshots/ipad/` |

Both sets were uploaded to App Store Connect; each device section shows 4/10 screenshots. Images use standard-range 8-bit RGB with no alpha. The sample accounts and posts are original synthetic data, visibly marked as examples. No real platform responses, account cookies, avatars or personal posts are used.

The generator is opt-in (`TIDEMELD_STORE_SCREENSHOTS=1`) and requires an absolute `TIDEMELD_SCREENSHOT_DIRECTORY`. Put these variables in the test runner environment in the generated `.xctestrun`; the parent shell environment alone is insufficient. Build for testing with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=''` so debug-only settings are not shown. Run only `TidemeldTests/StoreScreenshotTests`, with parallel testing disabled, on a simulator without real accounts.

Devices used:
- iPhone: existing `Tidemeld regression`, `4041A259-B0C0-40B3-81DA-B9258F6474F6`.
- iPad: new `Tidemeld Store iPad`, `A847E45C-A225-4C3D-8490-D6D563150D51`.

Never run tests on the two simulators identified as containing real sessions in `CLAUDE.md`. Screenshot data is injected by the test only; it is not an in-app demo or a feature restricted to reviewers. App Review notes state this explicitly.
