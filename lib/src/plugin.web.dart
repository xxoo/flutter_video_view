import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void _register() => platformViewRegistry.registerViewFactory(
  'video_view',
  (_, {Object? params}) => VideoViewPlugin.getInstance(params as int).dom,
);

@JS('VideoViewPlugin')
external JSFunction? get _pluginClass;

@JS()
extension type VideoViewPlugin._(JSObject _) implements JSObject {
  static void registerWith(Registrar registrar) {
    const requiredVersion = '1.2.0';
    const cmd = 'dart run video_view:webinit';
    var e = '';
    StackTrace? s;
    if (_pluginClass == null) {
      s = StackTrace.current; // VideoViewPlugin.js missing
      e = 'VideoViewPlugin.js is not loaded.\nPlease try runninng "$cmd" to install.';
    } else if (VideoViewPlugin.version != requiredVersion) {
      s = StackTrace.current; // VideoViewPlugin.js version mismatch
      e = 'VideoViewPlugin.js version: ${VideoViewPlugin.version}, requires $requiredVersion.\nPlease try running "$cmd" to update or cleaning the browser cache.';
    }
    if (s == null) {
      _register();
    } else if (kDebugMode) {
      Zone.current.handleUncaughtError(e, s);
    } else {
      FlutterError.reportError(
        FlutterErrorDetails(exception: e, stack: s, library: 'video_view'),
      );
      _register(); // try to register anyway
    }
  }

  external static VideoViewPlugin getInstance(int id);
  external static String? get version;
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
  external void setOverrideAudio(String? trackId);
  external void setOverrideSubtitle(String? trackId);
  external bool setDisplayMode(int displayMode);
  external void setStyle(String objectFit, int backgroundColor);
}
