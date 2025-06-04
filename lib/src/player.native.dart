// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'player.common.dart';
import 'player.interface.dart';

/// Native implementation of [VideoControllerInterface].
class VideoController extends VideoControllerInterface {
  static const _methodChannel = MethodChannel('VideoViewPlugin');
  static var _detectorStarted = false;

  @override
  get disposed => _disposed;
  var _disposed = false;

  @override
  get id => _id;
  int? _id;

  /// The id of the subtitle texture if available.
  /// This API is only available on native platforms and should be considered as private.
  int? get subId => _subId;
  int? _subId;

  StreamSubscription? _eventSubscription;
  String? _source;
  var _seeking = false;
  var _position = 0;

  VideoController({
    super.source,
    super.volume,
    super.speed,
    super.looping,
    super.autoPlay,
    super.position,
    super.showSubtitle,
    super.preferredSubtitleLanguage,
    super.preferredAudioLanguage,
    super.maxBitRate,
    super.maxResolution,
  }) {
    if (kDebugMode && !_detectorStarted) {
      _detectorStarted = true;
      final receivePort = ReceivePort();
      receivePort.listen((_) => _methodChannel.invokeMethod('dispose'));
      Isolate.spawn(
        (_) {},
        null,
        paused: true,
        onExit: receivePort.sendPort,
        debugName: 'Video_view restart detector',
      );
    }
    _methodChannel.invokeMethod('create').then((value) {
      if (disposed) {
        _methodChannel.invokeMethod('dispose', value['id']);
      } else {
        _subId = value['subId'];
        _id = value['id'];
        _eventSubscription = EventChannel('VideoViewPlugin/$id')
            .receiveBroadcastStream()
            .listen((event) {
              final e = event as Map;
              final eventName = e['event'] as String;
              if (eventName == 'mediaInfo') {
                if (_source == e['source']) {
                  loading.value = false;
                  playbackState.value = VideoControllerPlaybackState.paused;
                  mediaInfo.value = VideoControllerMediaInfo(
                    e['duration'],
                    VideoControllerAudioInfo.batchFromMap(e['audioTracks']),
                    VideoControllerSubtitleInfo.batchFromMap(
                      e['subtitleTracks'],
                    ),
                    _source!,
                  );
                  if (mediaInfo.value!.duration == 0) {
                    speed.value = 1;
                  }
                  if (autoPlay.value) {
                    play();
                  }
                }
              } else if (eventName == 'videoSize') {
                if (playbackState.value !=
                        VideoControllerPlaybackState.closed ||
                    loading.value) {
                  final width = e['width'] as double;
                  final height = e['height'] as double;
                  if (width != videoSize.value.width ||
                      height != videoSize.value.height) {
                    videoSize.value = width > 0 && height > 0
                        ? Size(width, height)
                        : Size.zero;
                  }
                }
              } else if (eventName == 'position') {
                if (mediaInfo.value != null) {
                  position.value = e['value'] > mediaInfo.value!.duration
                      ? mediaInfo.value!.duration
                      : e['value'] < 0
                      ? 0
                      : e['value'];
                }
              } else if (eventName == 'buffer') {
                if (mediaInfo.value != null) {
                  final start = e['start'] as int;
                  final end = e['end'] as int;
                  bufferRange.value = start == 0 && end == 0
                      ? VideoControllerBufferRange.empty
                      : VideoControllerBufferRange(start, end);
                }
              } else if (eventName == 'error') {
                // ignore errors when player is closed
                if (playbackState.value !=
                        VideoControllerPlaybackState.closed ||
                    loading.value) {
                  _source = null;
                  error.value = e['value'];
                  loading.value = false;
                  _close();
                }
              } else if (eventName == 'loading') {
                if (mediaInfo.value != null) {
                  loading.value = e['value'];
                }
              } else if (eventName == 'seekEnd') {
                if (mediaInfo.value != null) {
                  _seeking = false;
                  loading.value = false;
                }
              } else if (eventName == 'finished') {
                if (mediaInfo.value != null) {
                  finishedTimes.value += 1;
                  loading.value = false;
                  if (mediaInfo.value!.duration == 0) {
                    _close();
                  } else if (!looping.value) {
                    playbackState.value = VideoControllerPlaybackState.paused;
                  }
                }
              }
            });
        if (_source != null) {
          open(_source!);
          if (_position > 0) {
            seekTo(_position);
          }
        }
        _position = 0;
        if (volume.value != 1) {
          _setVolume();
        }
        if (speed.value != 1) {
          _setSpeed();
        }
        if (looping.value) {
          _setLooping();
        }
        if (maxBitRate.value > 0) {
          _setMaxBitRate();
        }
        if (maxResolution.value != Size.zero) {
          _setMaxResolution();
        }
        if (preferredAudioLanguage.value != null) {
          _setPreferredAudioLanguage();
        }
        if (preferredSubtitleLanguage.value != null) {
          _setPreferredSubtitleLanguage();
        }
        if (showSubtitle.value) {
          _setShowSubtitle();
        }
      }
    });
  }

  @override
  void dispose() {
    if (!disposed) {
      _disposed = true;
      _eventSubscription?.cancel();
      if (id != null) {
        _methodChannel.invokeMethod('dispose', id);
      }
      mediaInfo.dispose();
      videoSize.dispose();
      position.dispose();
      error.dispose();
      loading.dispose();
      playbackState.dispose();
      volume.dispose();
      speed.dispose();
      looping.dispose();
      autoPlay.dispose();
      finishedTimes.dispose();
      bufferRange.dispose();
      overrideAudio.dispose();
      overrideSubtitle.dispose();
      maxBitRate.dispose();
      maxResolution.dispose();
      preferredAudioLanguage.dispose();
      preferredSubtitleLanguage.dispose();
      showSubtitle.dispose();
    }
  }

  @override
  void close() {
    if (!disposed) {
      _source = null;
      if (id != null &&
          (playbackState.value != VideoControllerPlaybackState.closed ||
              loading.value)) {
        _methodChannel.invokeMethod('close', id);
        _close();
      }
      loading.value = false;
    }
  }

  @override
  void open(String source) {
    if (!disposed) {
      _source = source;
      if (id != null) {
        error.value = null;
        _close();
        _methodChannel.invokeMethod('open', {'id': id, 'value': source});
      }
      loading.value = true;
    }
  }

  @override
  bool play() {
    if (!disposed) {
      if (id != null &&
          playbackState.value == VideoControllerPlaybackState.paused) {
        _methodChannel.invokeMethod('play', id);
        playbackState.value = VideoControllerPlaybackState.playing;
        return true;
      } else if (!autoPlay.value &&
          playbackState.value == VideoControllerPlaybackState.closed &&
          _source != null) {
        setAutoPlay(true);
        return true;
      }
    }
    return false;
  }

  @override
  bool pause() {
    if (!disposed) {
      if (id != null &&
          playbackState.value == VideoControllerPlaybackState.playing) {
        _methodChannel.invokeMethod('pause', id);
        playbackState.value = VideoControllerPlaybackState.paused;
        if (!_seeking) {
          loading.value = false;
        }
        return true;
      } else if (autoPlay.value &&
          playbackState.value == VideoControllerPlaybackState.closed &&
          _source != null) {
        setAutoPlay(false);
        return true;
      }
    }
    return false;
  }

  @override
  bool seekTo(int position, {bool fast = false}) {
    if (!disposed) {
      if (id == null) {
        _position = position;
        return true;
      } else if (mediaInfo.value == null) {
        if (loading.value && position > 30) {
          _methodChannel.invokeMethod('seekTo', {
            'id': id,
            'position': position,
            'fast': true,
          });
          return true;
        }
      } else if (mediaInfo.value!.duration > 0) {
        if (position < 0) {
          position = 0;
        } else if (position > mediaInfo.value!.duration) {
          position = mediaInfo.value!.duration;
        }
        _methodChannel.invokeMethod('seekTo', {
          'id': id,
          'position': position,
          'fast': fast,
        });
        loading.value = true;
        _seeking = true;
        return true;
      }
    }
    return false;
  }

  @override
  bool setVolume(double value) {
    if (!disposed) {
      if (value < 0) {
        value = 0;
      } else if (value > 1) {
        value = 1;
      }
      volume.value = value;
      _setVolume();
      return true;
    }
    return false;
  }

  @override
  bool setSpeed(double value) {
    if (!disposed && mediaInfo.value?.duration != 0) {
      if (value < 0.5) {
        value = 0.5;
      } else if (value > 2) {
        value = 2;
      }
      speed.value = value;
      if (id != null) {
        _setSpeed();
      }
      return true;
    }
    return false;
  }

  @override
  bool setLooping(bool value) {
    if (!disposed && value != looping.value) {
      looping.value = value;
      if (id != null) {
        _setLooping();
      }
      return true;
    }
    return false;
  }

  @override
  bool setAutoPlay(bool value) {
    if (!disposed && value != autoPlay.value) {
      autoPlay.value = value;
      return true;
    }
    return false;
  }

  @override
  bool setMaxResolution(Size value) {
    if (!disposed &&
        value.width >= 0 &&
        value.height >= 0 &&
        (value.width != maxResolution.value.width ||
            value.height != maxResolution.value.height)) {
      maxResolution.value = value;
      if (id != null) {
        _setMaxResolution();
      }
      return true;
    }
    return false;
  }

  @override
  bool setMaxBitRate(int value) {
    if (!disposed && value >= 0 && value != maxBitRate.value) {
      maxBitRate.value = value;
      if (id != null) {
        _setMaxBitRate();
      }
      return true;
    }
    return false;
  }

  @override
  bool setPreferredAudioLanguage(String? value) {
    if (!disposed && value != preferredAudioLanguage.value) {
      preferredAudioLanguage.value = value;
      if (id != null) {
        _setPreferredAudioLanguage();
      }
      return true;
    }
    return false;
  }

  @override
  bool setPreferredSubtitleLanguage(String? value) {
    if (!disposed && value != preferredSubtitleLanguage.value) {
      preferredSubtitleLanguage.value = value;
      if (id != null) {
        _setPreferredSubtitleLanguage();
      }
      return true;
    }
    return false;
  }

  @override
  bool setShowSubtitle(bool value) {
    if (!disposed && value != showSubtitle.value) {
      showSubtitle.value = value;
      if (id != null) {
        _setShowSubtitle();
      }
      return true;
    }
    return false;
  }

  @override
  bool setOverrideAudio(String? trackId) => _overrideTrack(trackId, true);

  @override
  bool setOverrideSubtitle(String? trackId) => _overrideTrack(trackId, false);

  @override
  bool setFullscreen(bool value) => false;

  @override
  bool setPictureInPicture(bool value) => false;

  bool _overrideTrack(String? trackId, bool isAudio) {
    if (!disposed && mediaInfo.value != null) {
      final VideoControllerProperty<String?> overrided;
      final Map<String, Object> tracks;
      if (isAudio) {
        tracks = mediaInfo.value!.audioTracks;
        overrided = overrideAudio;
      } else {
        tracks = mediaInfo.value!.subtitleTracks;
        overrided = overrideSubtitle;
      }
      if (overrided.value != trackId) {
        bool enabled = trackId != null;
        final String tid;
        if (!enabled) {
          tid = overrided.value!;
        } else if (tracks.containsKey(trackId)) {
          tid = trackId;
        } else {
          return false;
        }
        final ids = tid.split('.');
        _methodChannel.invokeMethod('overrideTrack', {
          'id': id,
          'groupId': int.parse(ids[0]),
          'trackId': int.parse(ids[1]),
          'enabled': enabled,
        });
        overrided.value = trackId;
        return true;
      }
    }
    return false;
  }

  void _setMaxResolution() => _methodChannel.invokeMethod('setMaxResolution', {
    'id': id,
    'width': maxResolution.value.width,
    'height': maxResolution.value.height,
  });

  void _setMaxBitRate() => _methodChannel.invokeMethod('setMaxBitRate', {
    'id': id,
    'value': maxBitRate.value,
  });

  void _setVolume() => _methodChannel.invokeMethod('setVolume', {
    'id': id,
    'value': volume.value,
  });

  void _setSpeed() =>
      _methodChannel.invokeMethod('setSpeed', {'id': id, 'value': speed.value});

  void _setLooping() => _methodChannel.invokeMethod('setLooping', {
    'id': id,
    'value': looping.value,
  });

  void _setPreferredAudioLanguage() => _methodChannel.invokeMethod(
    'setPreferredAudioLanguage',
    {'id': id, 'value': preferredAudioLanguage.value ?? ''},
  );

  void _setPreferredSubtitleLanguage() => _methodChannel.invokeMethod(
    'setPreferredSubtitleLanguage',
    {'id': id, 'value': preferredSubtitleLanguage.value ?? ''},
  );

  void _setShowSubtitle() => _methodChannel.invokeMethod('setShowSubtitle', {
    'id': id,
    'value': showSubtitle.value,
  });

  void _close() {
    _seeking = false;
    mediaInfo.value = null;
    videoSize.value = Size.zero;
    position.value = 0;
    bufferRange.value = VideoControllerBufferRange.empty;
    finishedTimes.value = 0;
    playbackState.value = VideoControllerPlaybackState.closed;
    overrideAudio.value = overrideSubtitle.value = null;
  }
}
