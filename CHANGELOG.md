## 1.0.16
- minor improvements.

## 1.0.15
- disable download menu on Web platforms.
- use `document.fullscreenEnabled` and `document.pictureInPictureEnabled` to determine fullscreen and picture-in-picture availability on Web platforms.

## 1.0.14
- minor improvements on Web platforms.

## 1.0.13
- fix event handler leak on Web platforms.

## 1.0.12
- improve webinit command.
- improve online demo.

## 1.0.11
- fix a bug may cause audio and subtitle tracks out of sync on Web platforms.

## 1.0.10
- improve error handling on Web platforms.

## 1.0.9
- prefer previously selected track in `change` event of Web platforms.

## 1.0.8
- fix buffering message missing in some cases.

## 1.0.7
- improve format detection from url on Android.
- avoid buffering message for local files.

## 1.0.6
- fix a bug may cause subtitles not working on Android Chrome.

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