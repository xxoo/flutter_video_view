import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'player.dart';
import 'widget.native.dart' if (dart.library.js_interop) 'widget.web.dart';

/// The widget to display video for [VideoController].
///
/// This widget takes the whole space of its parent by default.
/// Which means you must put it in a container that has logical client size or set the size explicitly.
class VideoView extends StatefulWidget {
  final VideoController? controller;
  final String? source;
  final bool? autoPlay;
  final bool? looping;
  final double? volume;
  final double? speed;
  final int? position;
  final bool? showSubtitle;
  final bool? keepScreenOn;
  final String? preferredSubtitleLanguage;
  final String? preferredAudioLanguage;
  final int? maxBitRate;
  final Size? maxResolution;
  final void Function(VideoController)? onCreated;
  final bool? cancelableNotification;
  final bool? distinctNotification;
  final double width;
  final double height;
  final Color backgroundColor;
  final BoxFit videoFit;

  /// Create a new [VideoView] widget.
  ///
  /// [width] and [height] determine the size of the widget.
  /// [backgroundColor] is the color behind video.
  /// [videoFit] determines how to scale video.
  ///
  /// Other parameters only take efferts while initializing state.
  /// To changed them later, you need to call the corresponding methods of the controller.
  ///
  /// If [controller] is null or disposed, a new controller will be created.
  /// You can get it from [onCreated] callback.
  const VideoView({
    super.key,
    this.controller,
    this.source,
    this.autoPlay,
    this.looping,
    this.volume,
    this.speed,
    this.position,
    this.showSubtitle,
    this.keepScreenOn,
    this.preferredSubtitleLanguage,
    this.preferredAudioLanguage,
    this.maxBitRate,
    this.maxResolution,
    this.onCreated,
    this.cancelableNotification,
    this.distinctNotification,
    this.backgroundColor = Colors.black,
    this.videoFit = BoxFit.contain,
    this.width = double.infinity,
    this.height = double.infinity,
  });

  @override
  createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final VideoController _controller;
  var _foreignController = false;
  // This is a workaround for the fullscreen issue on web.
  OverlayEntry? _overlayEntry;

  void _fullscreenChange() {
    if (_controller.displayMode.value !=
        VideoControllerDisplayMode.fullscreen) {
      _clearOverlay();
    } else if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (context) => Container(
          color: Colors.transparent,
          width: double.infinity,
          height: double.infinity,
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    }
  }

  void _clearOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _update() => setState(() {});

  @pragma('vm:notify-debugger-on-exception')
  void _runOnCreated() {
    if (widget.onCreated != null) {
      try {
        widget.onCreated!(_controller);
      } catch (e, s) {
        if (!kDebugMode) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: e,
              stack: s,
              library: 'video_view',
              informationCollector: () => <DiagnosticsNode>[
                DiagnosticsProperty<void Function(VideoController)>(
                  'onCreate',
                  widget.onCreated!,
                ),
                DiagnosticsProperty<VideoController>(
                  'VideoController',
                  _controller,
                ),
                DiagnosticsProperty<VideoView>('VideoView', widget),
                DiagnosticsProperty<State>('State', this),
              ],
            ),
          );
        }
      }
    }
  }

  @override
  initState() {
    super.initState();
    if (widget.controller == null || widget.controller!.disposed) {
      _controller = VideoController(
        source: widget.source,
        autoPlay: widget.autoPlay,
        looping: widget.looping,
        volume: widget.volume,
        speed: widget.speed,
        position: widget.position,
        showSubtitle: widget.showSubtitle,
        keepScreenOn: widget.keepScreenOn,
        preferredSubtitleLanguage: widget.preferredSubtitleLanguage,
        preferredAudioLanguage: widget.preferredAudioLanguage,
        maxBitRate: widget.maxBitRate,
        maxResolution: widget.maxResolution,
        cancelableNotification: widget.cancelableNotification,
        distinctNotification: widget.distinctNotification,
      );
    } else {
      _foreignController = true;
      _controller = widget.controller!;
      _controller.initialize(
        source: widget.source,
        autoPlay: widget.autoPlay,
        looping: widget.looping,
        volume: widget.volume,
        speed: widget.speed,
        position: widget.position,
        showSubtitle: widget.showSubtitle,
        keepScreenOn: widget.keepScreenOn,
        preferredSubtitleLanguage: widget.preferredSubtitleLanguage,
        preferredAudioLanguage: widget.preferredAudioLanguage,
        maxBitRate: widget.maxBitRate,
        maxResolution: widget.maxResolution,
        cancelableNotification: widget.cancelableNotification,
        distinctNotification: widget.distinctNotification,
      );
    }
    _runOnCreated();
    _controller.videoSize.addListener(_update);
    _controller.showSubtitle.addListener(_update);
    if (kIsWeb) {
      _controller.displayMode.addListener(_fullscreenChange);
    }
  }

  @override
  dispose() {
    if (!_foreignController) {
      _controller.dispose();
    } else if (!_controller.disposed) {
      _controller.videoSize.removeListener(_update);
      _controller.showSubtitle.removeListener(_update);
      if (kIsWeb) {
        _controller.displayMode.removeListener(_fullscreenChange);
        _clearOverlay();
      }
    }
    super.dispose();
  }

  @override
  build(_) => Container(
    width: widget.width,
    height: widget.height,
    color: widget.backgroundColor,
    child: _controller.disposed || _controller.videoSize.value == Size.zero
        ? null
        : makeWidget(_controller, widget.videoFit, widget.backgroundColor),
  );
}
