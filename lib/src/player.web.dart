// ignore_for_file: invalid_use_of_protected_member

import 'dart:js_interop';
import 'dart:ui_web';
import 'package:flutter/widgets.dart';
import 'player.common.dart';
import 'player.interface.dart';
import 'plugin.web.dart';

/// Web implementation of [VideoControllerInterface].
class VideoController extends VideoControllerInterface {
  @override
  get disposed => _disposed;
  var _disposed = false;

  @override
  get id => _plugin.id;
  late final _plugin = VideoViewPlugin.create(
    (JSObject message) {
      final e = message.dartify() as Map;
      final eventName = e['event'] as String;
      if (eventName == 'error') {
        // ignore errors when player is closed
        if (playbackState.value != VideoControllerPlaybackState.closed ||
            loading.value) {
          _source = null;
          error.value = e['value'];
          loading.value = false;
          _close();
        }
      } else if (eventName == 'mediaInfo') {
        if (_source != null && _translateSource(_source!) == e['source']) {
          loading.value = false;
          playbackState.value = VideoControllerPlaybackState.paused;
          mediaInfo.value = VideoControllerMediaInfo(
            (e['duration'] as double).toInt(),
            VideoControllerAudioInfo.batchFromMap(e['audioTracks']),
            VideoControllerSubtitleInfo.batchFromMap(e['subtitleTracks']),
            _source!,
          );
          if (mediaInfo.value!.duration == 0) {
            speed.value = 1;
          }
        }
      } else if (eventName == 'videoSize') {
        if (playbackState.value != VideoControllerPlaybackState.closed ||
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
          final v = (e['value'] as double).toInt();
          position.value = v > mediaInfo.value!.duration
              ? mediaInfo.value!.duration
              : v < 0
              ? 0
              : v;
        }
      } else if (eventName == 'buffer') {
        if (mediaInfo.value != null) {
          final start = (e['start'] as double).toInt();
          final end = (e['end'] as double).toInt();
          bufferRange.value = start == 0 && end == 0
              ? VideoControllerBufferRange.empty
              : VideoControllerBufferRange(start, end);
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
      } else if (eventName == 'playing') {
        if (mediaInfo.value != null) {
          loading.value = _seeking = _loading = false;
          playbackState.value = e['value']
              ? VideoControllerPlaybackState.playing
              : VideoControllerPlaybackState.paused;
        }
      } else if (eventName == 'loading') {
        if (mediaInfo.value != null) {
          _loading = e['value'];
          loading.value = _loading || _seeking;
        }
      } else if (eventName == 'seeking') {
        if (mediaInfo.value != null) {
          _seeking = e['value'];
          loading.value = _loading || _seeking;
        }
      } else if (eventName == 'speed') {
        speed.value = e['value'];
      } else if (eventName == 'volume') {
        volume.value = e['value'];
      } else if (eventName == 'displayMode') {
        displayMode.value =
            VideoControllerDisplayMode.values[(e['value'] as double).toInt()];
      } else if (eventName == 'showSubtitle') {
        showSubtitle.value = e['value'];
      } else if (eventName == 'overrideAudio') {
        _overrideTrack(e['value'], true);
      } else if (eventName == 'overrideSubtitle') {
        _overrideTrack(e['value'], false);
      }
    }.toJS,
  );

  String? _source;
  var _seeking = false;
  var _loading = false;

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
  });

  @override
  dispose() {
    if (!disposed) {
      _disposed = true;
      VideoViewPlugin.destroy(_plugin);
      _plugin.close();
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
      maxBitRate.dispose();
      maxResolution.dispose();
      preferredAudioLanguage.dispose();
      preferredSubtitleLanguage.dispose();
      showSubtitle.dispose();
      overrideAudio.dispose();
      overrideSubtitle.dispose();
      displayMode.dispose();
    }
  }

  @override
  close() {
    if (!disposed) {
      _source = null;
      if (playbackState.value != VideoControllerPlaybackState.closed ||
          loading.value) {
        _plugin.close();
        _close();
      }
      loading.value = false;
    }
  }

  @override
  open(source) {
    if (!disposed) {
      _source = source;
      error.value = null;
      _close();
      _plugin.open(_translateSource(source));
      loading.value = true;
    }
  }

  @override
  play() {
    if (!disposed) {
      if (playbackState.value == VideoControllerPlaybackState.paused) {
        _plugin.play();
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
  pause() {
    if (!disposed) {
      if (playbackState.value == VideoControllerPlaybackState.playing) {
        _plugin.pause();
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
  seekTo(value, {fast = false}) {
    if (!disposed) {
      if (mediaInfo.value == null) {
        // ignore position if it's less than 30 ms
        if (loading.value && value > 30) {
          _plugin.seekTo(value, true);
          return true;
        }
      } else if (mediaInfo.value!.duration > 0) {
        if (value < 0) {
          value = 0;
        } else if (value > mediaInfo.value!.duration) {
          value = mediaInfo.value!.duration;
        }
        _plugin.seekTo(value, fast);
        return true;
      }
    }
    return false;
  }

  @override
  setAutoPlay(value) {
    if (!disposed && value != autoPlay.value) {
      autoPlay.value = value;
      _plugin.setAutoPlay(value);
      return true;
    }
    return false;
  }

  @override
  setLooping(value) {
    if (!disposed && value != looping.value) {
      looping.value = value;
      _plugin.setLooping(value);
      return true;
    }
    return false;
  }

  @override
  setShowSubtitle(value) {
    if (!disposed && value != showSubtitle.value) {
      showSubtitle.value = value;
      _plugin.setShowSubtitle(value);
      return true;
    }
    return false;
  }

  @override
  setSpeed(value) {
    if (!disposed && mediaInfo.value?.duration != 0) {
      _plugin.setSpeed(value);
      return true;
    }
    return false;
  }

  @override
  setVolume(value) {
    if (!disposed) {
      _plugin.setVolume(value);
      return true;
    }
    return false;
  }

  @override
  setMaxBitRate(value) {
    if (!disposed && value >= 0 && value != maxBitRate.value) {
      maxBitRate.value = value;
      _plugin.setMaxBitRate(value);
    }
    return false;
  }

  @override
  setMaxResolution(value) {
    if (!disposed &&
        value.width >= 0 &&
        value.height >= 0 &&
        (value.width != maxResolution.value.width ||
            value.height != maxResolution.value.height)) {
      maxResolution.value = value;
      _plugin.setMaxResolution(value.width.toInt(), value.height.toInt());
    }
    return false;
  }

  @override
  setPreferredAudioLanguage(value) {
    if (!disposed && value != preferredAudioLanguage.value) {
      preferredAudioLanguage.value = value;
      _plugin.setPreferredAudioLanguage(value ?? '');
      return true;
    }
    return false;
  }

  @override
  setPreferredSubtitleLanguage(value) {
    if (!disposed && value != preferredSubtitleLanguage.value) {
      preferredSubtitleLanguage.value = value;
      _plugin.setPreferredSubtitleLanguage(value ?? '');
      return true;
    }
    return false;
  }

  @override
  setOverrideAudio(trackId) {
    if (!disposed) {
      final result = _overrideTrack(trackId, true);
      if (result) {
        _plugin.setOverrideAudio(trackId);
      }
      return result;
    }
    return false;
  }

  @override
  setOverrideSubtitle(trackId) {
    if (!disposed) {
      final result = _overrideTrack(trackId, false);
      if (result) {
        _plugin.setOverrideSubtitle(trackId);
      }
      return result;
    }
    return false;
  }

  @override
  setDisplayMode(value) {
    if (!disposed && videoSize.value != Size.zero) {
      return _plugin.setDisplayMode(
        VideoControllerDisplayMode.values.indexOf(value),
      );
    }
    return false;
  }

  /// Set the background color of the player.
  /// This API is only available on web and should be considered as private.
  void setBackgroundColor(Color color) {
    if (!disposed) {
      _plugin.setBackgroundColor(color.toARGB32());
    }
  }

  /// Set the content fit of the player.
  /// This API is only available on web and should be considered as private.
  void setVideoFit(BoxFit fit) {
    if (!disposed) {
      _plugin.setVideoFit(fit.name);
    }
  }

  bool _overrideTrack(String? trackId, bool isAudio) {
    if (mediaInfo.value != null) {
      final VideoControllerProperty<String?> overrided;
      final Map<String, Object> tracks;
      if (isAudio) {
        tracks = mediaInfo.value!.audioTracks;
        overrided = overrideAudio;
      } else {
        tracks = mediaInfo.value!.subtitleTracks;
        overrided = overrideSubtitle;
      }
      if (trackId != overrided.value &&
          (trackId == null || tracks.containsKey(trackId))) {
        overrided.value = trackId;
        return true;
      }
    }
    return false;
  }

  void _close() {
    _seeking = _loading = false;
    mediaInfo.value = null;
    videoSize.value = Size.zero;
    position.value = 0;
    bufferRange.value = VideoControllerBufferRange.empty;
    finishedTimes.value = 0;
    playbackState.value = VideoControllerPlaybackState.closed;
    overrideAudio.value = overrideSubtitle.value = null;
    displayMode.value = VideoControllerDisplayMode.normal;
  }
}

String _translateSource(String asset) {
  if (asset.startsWith('asset://')) {
    return AssetManager().getAssetUrl(asset.substring(8));
  }
  return asset;
}
