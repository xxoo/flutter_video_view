<p align="center"><a href="https://github.com/xxoo/flutter_video_view"><img src="logo.svg" alt="video_view" width="128" /></a></p>

<p align="center">
	<img src="https://img.shields.io/pub/v/video_view" alt="pub version">
	<img src="https://img.shields.io/pub/likes/video_view" alt="pub likes">
	<img src="https://img.shields.io/github/stars/xxoo/flutter_video_view" alt="github stars">
	<img src="https://img.shields.io/pub/dm/video_view" alt="pub downloads">
</p>

`video_view` is a lightweight media player with subtitle rendering<sup><a id="subtitle-source-0" href="#subtitle-0">[1]</a></sup> and audio track switching support, leveraging system or app-level components for seamless playback. For API documentation, please visit [here](https://pub.dev/documentation/video_view/latest/video_view/).

#### Key benefits:
- Complete platform coverage: Android, iOS, macOS, Windows, Web, Linux.
- Internal subtitle rendering, audio track switching, max bitrate/resolution limits.
- Fine-grained status notification with reentrancy prevention.
- Small, widget-first API: drop-in `VideoView(source: ...)` to start.

**NOTE:** `video_view` requires Flutter 3.32 or higher.
___

### Demo
You may try the [online demo](https://xxoo.github.io/flutter_video_view/), or run the demo app locally by cloning this repository:
```shell
git clone -c core.symlinks=true https://github.com/xxoo/flutter_video_view.git
cd flutter_video_view/example
flutter pub get
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
3. If your project has web support, you may also need to initialize the web entry point by running the following command after installing or updating this package:
```shell
dart run video_view:webinit
```
___

### Sample code

Default controller:
```dart
import 'package:flutter/widgets.dart';
import 'package:video_view/video_view.dart';

void main() => runApp(VideoView(
	source: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
	autoPlay: true,
	looping: true,
));
```

Custom controller:
```dart
import 'package:flutter/material.dart';
import 'package:video_view/video_view.dart';

void main() => runApp(MaterialApp(builder: (_, _) => const MyApp()));

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _player = VideoController();

  @override
  initState() {
    super.initState();
    _player.open(
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    );
    _player.playbackState.addListener(() => setState(() {}));
  }

  @override
  dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  build(_) => Stack(
    alignment: Alignment.center,
    children: [
      VideoView(controller: _player),
      IconButton(
        iconSize: 64,
        icon: const Icon(Icons.play_arrow),
        isSelected:
            _player.playbackState.value == VideoControllerPlaybackState.playing,
        selectedIcon: const Icon(Icons.pause),
        onPressed: () =>
            _player.playbackState.value == VideoControllerPlaybackState.playing
            ? _player.pause()
            : _player.play(),
      ),
    ],
  );
}
```
___

### Platform support

| **Platform** | **Version** | **Backend**                                                                  |
| ------------ | ----------- | ---------------------------------------------------------------------------- |
| Android      | 7+          | [ExoPlayer](https://developer.android.com/media/media3/exoplayer)            |
| iOS          | 15+         | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/) |
| macOS        | 12+         | [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer/) |
| Windows | 10+ | [MediaPlayer](https://learn.microsoft.com/uwp/api/windows.media.playback.mediaplayer)<sup><a id="mediaplayer-source-0" href="#mediaplayer-0">[2]</a></sup> |
| Linux        | N/A         | [mpv](https://github.com/mpv-player/mpv/tree/master/include/mpv)<sup><a id="mpv-source-0" href="#mpv-0">[3]</a></sup> |
| Web | Chrome 84+ / Safari 15+ / Firefox 90+ | [\<video>](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/video), [ShakaPlayer](https://shaka-player-demo.appspot.com/docs/api/shaka.Player.html)<sup><a id="shaka-source-0" href="#shaka-0">[4]</a></sup> |
___

### Supported media formats

*For user who only cares about Android and iOS, the following formats are supported without condition:*
| **Type**         | **Formats**          |
| ---------------- | -------------------- |
| Video Codec      | h.264, h.265         |
| Audio Codec      | aac, mp3             |
| Container Format | mp4, ts              |
| Subtitle Format  | WebVTT, CEA-608/708  |
| Stream Protocol  | HLS, LL-HLS          |
| URL Scheme       | http(s), file, asset |

*A more complete list with conditions:*
| **Type**         | **Formats**                                          |
| ---------------- | ---------------------------------------------------- |
| Video Codec      | h.264, h.265<sup><a id="h265-source-0" href="#h265-0">[5]</a></sup>, av1<sup><a id="apple-source-0" href="#apple-0">[6]</a></sup> |
| Audio Codec      | aac, mp3                                             |
| Container Format | mp4, ts, webm<sup><a id="apple-source-1" href="#apple-1">[6]</a></sup> |
| Subtitle Format  | WebVTT<sup><a id="vtt-source-0" href="#vtt-0">[7]</a></sup>, CEA-608/708                            |
| Stream Protocol  | HLS, LL-HLS, DASH<sup><a id="avplayer-source-0" href="#avplayer-0">[8]</a></sup>, MSS<sup><a id="avplayer-source-1" href="#avplayer-1">[8]</a><a id="shaka-source-1" href="#shaka-1">[4]</a></sup> |
| URL Scheme       | http(s), file, asset                                 |
___

### How to specify format manually

Most backends don't support manually specifying media format, with Android and Web being the exceptions. Therefore, no formal API planned for this feature. However, supported platforms can still automatically detect stream format from URL. You may simply append a file extension to the query string or hash fragment to specify the format. Please note that only 3 extensions are recognized: `.m3u8`, `.mpd`, and `.ism/manifest`. If multiple extensions are found, the last one takes precedence. For example:
```dart
// No need to specify format, the url already contains `.m3u8`
final example0 = 'https://example.com/video.m3u8';

// Missing extension in path, add `.m3u8` in hash fragment
final example1 = 'https://example.com/video#.m3u8';

// Or in query string
final example1 = 'https://example.com/video?.m3u8';

// Override HLS to DASH
final example2 = 'https://example.com/video.m3u8#.mpd';
```
___

### Footnotes

1. <a id="subtitle-0" href="#subtitle-source-0">^</a> Only internal subtitle tracks are supported.
2. <a id="mediaplayer-0" href="#mediaplayer-source-0">^</a> `MediaPlayer` may lead to crash on certain Windows builds when rendering subtitles.
3. <a id="mpv-0" href="#mpv-source-0">^</a> `video_view` requires `mpv`(v0.4+) or `libmpv`(aka `mpv-libs`) on Linux. Developers integrating this plugin into Linux app should install `libmpv-dev`(aka `mpv-libs-devel`) instead. If unavailable in your package manager, please build `mpv` from source. For details refer to [mpv-build](https://github.com/mpv-player/mpv-build).
4. <a id="shaka-0" href="#shaka-source-0">^</a> <a id="shaka-1" href="#shaka-source-1">^</a> `video_view` requires [ShakaPlayer](https://cdn.jsdelivr.net/npm/shaka-player/dist/shaka-player.compiled.js) to enable HLS and DASH support on web platforms. For MSS support, please use [ShakaPlayer v4.x](https://cdn.jsdelivr.net/npm/shaka-player@4/dist/shaka-player.compiled.js) instead.
5. <a id="h265-0" href="#h265-source-0">^</a> Windows user may need to install a free [h.265 decoder](https://apps.microsoft.com/detail/9n4wgh0z6vhq) from Microsoft Store. Web platforms may lack h.265 support except for Apple webkit.
6. <a id="apple-0" href="#apple-source-0">^</a> <a id="apple-1" href="#apple-source-1">^</a> Apple platforms may lack webm and av1 support.
7. <a id="vtt-0" href="#vtt-source-0">^</a> WebVTT subtitles within HLS are not supported by Linux backend.
8. <a id="avplayer-0" href="#avplayer-source-0">^</a> <a id="avplayer-1" href="#avplayer-source-1">^</a> DASH and MSS are not supported by iOS/macOS backend.