import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

@JS()
extension type VideoViewPlugin._(JSObject _) implements JSObject {
  static void registerWith(
    Registrar registrar,
  ) => platformViewRegistry.registerViewFactory('VideoViewPlugin', (
    _, {
    Object? params,
  }) {
    const requiredVersion = '1.2.9';
    if (version != requiredVersion) {
      Zone.current.handleUncaughtError(
        'VideoViewPlugin.js version: $version. Required: $requiredVersion.\nPlease try cleaning the browser cache or using "dart run video_view:webinit" to update.',
        StackTrace.current,
      );
    }
    return VideoViewPlugin.getInstance(params as int).dom;
  });

  external static String? get version;
  external static VideoViewPlugin getInstance(int id);
  external int get id;
  external JSObject get dom;
  external VideoViewPlugin(JSFunction onmessage);
  external void dispose();
  external void play();
  external void pause();
  external void open(String source);
  external void close();
  external void seekTo(int position, bool fast);
  external void setVolume(double volume);
  external void setSpeed(double speed);
  external void setLooping(bool looping);
  external void setAutoPlay(bool autoPlay);
  external void setMaxResolution(int width, int height);
  external void setMaxBitRate(int bitrate);
  external void setPreferredAudioLanguage(String language);
  external void setPreferredSubtitleLanguage(String language);
  external void setShowSubtitle(bool show);
  external void setKeepScreenOn(bool keepOn);
  external void setOverrideAudio(String? trackId);
  external void setOverrideSubtitle(String? trackId);
  external bool setDisplayMode(int displayMode);
  external void setStyle(String objectFit, int backgroundColor);
}
