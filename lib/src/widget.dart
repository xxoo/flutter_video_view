import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:set_state_async/set_state_async.dart';
import 'player.common.dart';
import 'player.native.dart' if (dart.library.js_interop) 'player.web.dart';
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
  final String? preferredSubtitleLanguage;
  final String? preferredAudioLanguage;
  final int? maxBitRate;
  final Size? maxResolution;
  final void Function(VideoController)? onCreated;
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
    this.preferredSubtitleLanguage,
    this.preferredAudioLanguage,
    this.maxBitRate,
    this.maxResolution,
    this.onCreated,
    this.backgroundColor = Colors.black,
    this.videoFit = BoxFit.contain,
    this.width = double.infinity,
    this.height = double.infinity,
  });

  @override
  createState() => _VideoControllerState();
}

class _VideoControllerState extends State<VideoView> with SetStateAsync {
  late final VideoController _controller;
  bool _foreignController = false;
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
        preferredSubtitleLanguage: widget.preferredSubtitleLanguage,
        preferredAudioLanguage: widget.preferredAudioLanguage,
        maxBitRate: widget.maxBitRate,
        maxResolution: widget.maxResolution,
      );
    } else {
      _controller = widget.controller!;
      _foreignController = true;
      if (widget.source != null) {
        _controller.open(widget.source!);
      }
      if (widget.autoPlay != null) {
        _controller.setAutoPlay(widget.autoPlay!);
      }
      if (widget.looping != null) {
        _controller.setLooping(widget.looping!);
      }
      if (widget.volume != null) {
        _controller.setVolume(widget.volume!);
      }
      if (widget.speed != null) {
        _controller.setSpeed(widget.speed!);
      }
      if (widget.position != null) {
        _controller.seekTo(widget.position!);
      }
      if (widget.showSubtitle != null) {
        _controller.setShowSubtitle(widget.showSubtitle!);
      }
      if (widget.preferredSubtitleLanguage != null) {
        _controller.setPreferredSubtitleLanguage(
          widget.preferredSubtitleLanguage!,
        );
      }
      if (widget.preferredAudioLanguage != null) {
        _controller.setPreferredAudioLanguage(widget.preferredAudioLanguage!);
      }
      if (widget.maxBitRate != null) {
        _controller.setMaxBitRate(widget.maxBitRate!);
      }
      if (widget.maxResolution != null) {
        _controller.setMaxResolution(widget.maxResolution!);
      }
    }
    if (widget.onCreated != null) {
      widget.onCreated!(_controller);
    }
    _controller.videoSize.addListener(setStateAsync);
    _controller.showSubtitle.addListener(setStateAsync);
    if (kIsWeb) {
      _controller.displayMode.addListener(_fullscreenChange);
    }
  }

  @override
  dispose() {
    if (!_foreignController) {
      _controller.dispose();
    } else if (!_controller.disposed) {
      _controller.videoSize.removeListener(setStateAsync);
      _controller.showSubtitle.removeListener(setStateAsync);
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
    child: _controller.videoSize.value == Size.zero
        ? null
        : makeWidget(_controller, widget.videoFit, widget.backgroundColor),
  );
}
