# 1.2.3
- improve live stream handling

# 1.2.2
- convert logo file to webp format

# 1.2.1
- fix a bug may cause `objectFit` not working as expected.

# 1.2.0
- **breaking change:** use `async_value_notifier` package for state management which avoids synchronous listener re‑entrancy corrupting sequential logic and supplies advanced options for notification.
- add `VideoViewPlugin.js` version check.

# 1.1.8
- support mpv v0.4.x on Linux.
- fix error handling while opening media files on Web platforms.

# 1.1.7
- fix a bug on Windows may cause unexpected behavior when calling `setPreferredAudioLanguage()`.

# 1.1.6
- fix a bug on Windows may cause unexpected behavior when calling `setMaxResolution()` and `setMaxBitrate()`.

# 1.1.5
- no longer set `showSubtitle` to `true` automatically while calling `setOverrideSubtitle()` on Web platforms to keep the behavior consistent with other platforms.
- no longer crash on unsupported Windows (win10 redstone 2 or earlier).

# 1.1.4
- gl context initialization on Linux is now moved to open method of `VideoController` class. which means you may listen `error` event for `gl context not available` message and retry as needed. `VideoController` will not automatically retry anymore.
- fix unexpected position change while switching video tracks on Linux.

# 1.1.3
- fix a bug may lead to crash when failed to initialize gl context on Linux.
- automatically retry when failed to initialize gl context on Linux for at most 4095 times.

# 1.1.2
- fix a bug while triggering `displayMode` change event on Web platforms running in wasm mode. 

# 1.1.1
- fix a resource leak while disposing `VideoController`

# 1.1.0
- **breaking change:** replace `fullscreen` and `pictureInPicture` with `displayMode` in `VideoController` class.
- **breaking change:** replace `setFullscreen()` and `setPictureInPicture()` with `setDisplayMode()` in `VideoController` class.
- fix a bug may cause video stop playing on Web platforms when `videoFit` changes.
- fix a bug may cause `BoxFit.fitWidth` and `BoxFit.fitHeight` not working as expected with fullscreen on Web platforms.

# 1.0.16
- minor improvements.

# 1.0.15
- disable download menu on Web platforms.
- use `document.fullscreenEnabled` and `document.pictureInPictureEnabled` to determine fullscreen and picture-in-picture availability on Web platforms.

# 1.0.14
- minor improvements on Web platforms.

# 1.0.13
- fix event handler leak on Web platforms.

# 1.0.12
- improve webinit command.
- improve online demo.

# 1.0.11
- fix a bug may cause audio and subtitle tracks out of sync on Web platforms.

# 1.0.10
- improve error handling on Web platforms.

# 1.0.9
- prefer previously selected track in `change` event of Web platforms.

# 1.0.8
- fix buffering message missing in some cases.

# 1.0.7
- improve format detection from url on Android.
- avoid buffering message for local files.

# 1.0.6
- fix a bug may cause subtitles not working on Android Chrome.

# 1.0.5
- improve example.

# 1.0.4
- improve example.

# 1.0.3
- improve example.

# 1.0.2
- improve example.

# 1.0.1
- fix a bug in Safari may cause loading error.

# 1.0.0
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