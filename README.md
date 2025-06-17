### About

`video_view` is a lightweight media player with subtitle rendering[^subtitle] and audio track switching support, leveraging system or app-level components for seamless playback.
For API documentation, please visit [here](https://pub.dev/documentation/video_view/latest/video_view/).

**NOTE:** `video_view` requires Flutter 3.32 or higher. For older versions, please use [av_media_player](https://pub.dev/packages/av_media_player) instead.
___

### Demo
You may try the [online demo](https://xxoo.github.io/flutter_video_view/), or run the demo app locally by cloning this repository:
```shell
git clone -c core.symlinks=true https://github.com/xxoo/flutter_video_view.git
cd flutter_video_view/example
```
For basic usage, just run:
```shell
flutter run
```
For advanced usage, please run:
```shell
flutter run lib/main_advanced.dart
```
___

### Installation

1. Add dependency in your project by running:
```shell
flutter pub add video_view
```
2. Reference `video_view` in your Dart code:
```dart
import 'package:video_view/video_view.dart';
```
3. If your project has web support, you may also need to initialize the web entry point by running the following command after installing or updating `video_view` package:
```shell
dart run video_view:webinit
```
4. If you encounter ***"setState while widget is [building](https://www.google.com/search?q=setState()+or+markNeedsBuild()+called+during+build) or [locked](https://www.google.com/search?q=setState()+or+markNeedsBuild()+called+when+widget+tree+was+locked)"*** issue, then you probably need to install [`set_state_async`](https://pub.dev/packages/set_state_async) package as well.
___

### Platform support

| **Platform** | **Version** | **Backend**                                                                           |
| ------------ | ----------- | ------------------------------------------------------------------------------------- |
| Android      | 6+          | [ExoPlayer](https://developer.android.com/media/media3/exoplayer)                     |
| iOS          | 15+         | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)          |
| macOS        | 12+         | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/)          |
| Windows      | 10+         | [MediaPlayer](https://learn.microsoft.com/uwp/api/windows.media.playback.mediaplayer) |
| Linux        | N/A         | [libmpv](https://github.com/mpv-player/mpv/tree/master/include/mpv)[^libmpv]          |
| Web | Chrome 84+ / Safari 15+ / Firefox 90+ | [\<video>](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/video), [ShakaPlayer](https://shaka-player-demo.appspot.com/docs/api/shaka.Player.html)[^shaka] |
___

### Supported media formats

***For user who only cares about Android and iOS, the following formats are supported without condition:***
| **Type**          | **Formats**         |
| ----------------- | ------------------- |
| Video Codec       | H.264, H.265        |
| Audio Codec       | AAC, MP3            |
| Container Format  | MP4, TS             |
| Subtitle Format   | WebVTT, CEA-608/708 |
| Transfer Protocol | HTTP, HLS, LL-HLS   |

***A more complete list with conditions:***
| **Type**          | **Formats**                                        |
| ----------------- | -------------------------------------------------- |
| Video Codec       | H.264, H.265(HEVC)[^h265], AV1[^apple]             |
| Audio Codec       | AAC, MP3                                           |
| Container Format  | MP4, TS, WebM[^apple]                              |
| Subtitle Format   | WebVTT[^vtt], CEA-608/708                          |
| Transfer Protocol | HTTP, HLS, LL-HLS, DASH[^avplayer], MSS[^avplayer] |
___

### How to specify format manually

Most backends don't support manually specifying media format, with Android and Web being the exceptions. Therefore, there's no formal API planned for this feature. However, supported platforms can automatically detect the format from the URL. You can simply append a file extension to the query string or hash fragment to specify the format. Please note that only 3 extensions are recognized: `.m3u8`, `.mpd`, and `.ism/manifest`. If multiple extensions are found, the last one takes precedence. For example:
```dart
// No need to specify format, the url already contains `.m3u8`
final example0 = 'https://example.com/video.m3u8';

// Missing extension in path, add `.m3u8` in query string
final example1 = 'https://example.com/video?x=.m3u8';

// Override HLS to DASH format with query string
final example2 = 'https://example.com/video.m3u8?y=.mpd';

// Override HLS to DASH format with hash fragment
final example3 = 'https://example.com/video.m3u8#.mpd';
```

[^subtitle]: Only internal subtitle tracks are supported.
[^libmpv]: `video_view` requires `libmpv`(aka `mpv-libs`) on Linux. Developers integrating this plugin into Linux app should install `libmpv-dev`(aka `mpv-libs-devel`) instead. If unavailable in your package manager, please build `libmpv` from source. For details refer to [mpv-build](https://github.com/mpv-player/mpv-build).
[^shaka]: `video_view` requires [ShakaPlayer](https://cdn.jsdelivr.net/npm/shaka-player/dist/shaka-player.compiled.js) v4.15 or higher to enable HLS, DASH, MSS support on web platforms.
[^h265]: Windows user may need to install a free [H.265 decoder](https://apps.microsoft.com/detail/9n4wgh0z6vhq) from Microsoft Store. Web platforms may lack H.265 support except for Apple webkit.
[^apple]: Apple platforms may lack WebM and AV1 support.
[^vtt]: WebVTT subtitles within HLS are not supported by Linux backend.
[^avplayer]: DASH and MSS are not supported by iOS/macOS backend.