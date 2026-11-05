# Platform source icons

The X and Sina Weibo SVG paths are from [Simple Icons](https://github.com/simple-icons/simple-icons), retrieved on 2026-11-05:

- [X SVG](https://github.com/simple-icons/simple-icons/blob/develop/icons/x.svg)
- [Sina Weibo SVG](https://github.com/simple-icons/simple-icons/blob/develop/icons/sinaweibo.svg)
- [CC0-1.0 license](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md), included in [licenses/simple-icons-CC0.txt](../licenses/simple-icons-CC0.txt).

These marks identify the source of a post, not the app's identity or an endorsement. Brand names and trademarks belong to their respective owners.

The canonical SVG files live in `ios/Tidemeld/Resources/Assets.xcassets/Platform*.imageset/`. iOS preserves vector data and renders them as template images; Android uses vector drawables generated from the same paths with `python3 tools/sync-platform-icons.py`. No bitmap assets or network requests are used.

Platform adapters supply the icon and its accessible name to the shared `PostHeader`, which owns its size, tint and placement. The vector fits within 16pt on iOS or 16dp on Android, centered in a 32pt/dp layout slot; it preserves its aspect ratio and does not scale with the avatar or text. The source mark is not a separate button.
