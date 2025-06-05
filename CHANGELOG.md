## 1.0.5
- improve example.

## 1.0.4
- improve example.

## 1.0.3
- improve example.

## 1.0.2
- improve example.

## 1.0.1
- fix a bug in Safari may cause loading error.

## 1.0.0
- architecture upgrade, and add web support. (wasm compatible)
- provides better performance on android, but requires flutter 3.32 or higher.
- support fast seek on all platforms except chrome and windows.
- added `width` and `height` parameters to `VideoView` class.
- **breaking change:** file structure adjustment, no longer support high-granularity import. now the only entry is `video_view.dart`.
- **breaking change:** `SetStateSync` mixin is a standalone package now, please install it separately if needed.
- **breaking change:** replace `sizingMode` with `videoFit` in `VideoView` class.
- **braaking change:** removed video tracks from `VideoControllerMediaInfo.tracks` since they're not supported on many platforms. which means it's no longer possible to switch video tracks via `overrideTrack()`. however, `setMaxResolution()` and `setMaxBitrate()` are still available.
- **breaking change:** replace `overrideTracks` with `overrideAudio` and `overrideSubtitle` in `VideoController` class.
- **breaking change:** replace `overrideTrack()` with `setOverrideAudio()` and `setOverrideSubtitle()` in `VideoController` class.