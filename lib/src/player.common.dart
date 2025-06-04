/// @docImport 'player.interface.dart';
library;

import 'package:flutter/widgets.dart';

/// This type is used by [VideoControllerInterface.playbackState].
enum VideoControllerPlaybackState { playing, paused, closed }

/// This class is used by [VideoControllerInterface] to notify listeners when
/// property changes. The [value] setter is protected, you may see warnings
/// when trying to assign value to it.
class VideoControllerProperty<T> extends ValueNotifier<T> {
  VideoControllerProperty(super.value);

  @override
  @protected
  set value(T newValue) => super.value = newValue;
}

/// This type is used by [VideoControllerInterface.bufferRange].
class VideoControllerBufferRange {
  static const empty = VideoControllerBufferRange(0, 0);

  final int start;
  final int end;
  const VideoControllerBufferRange(this.start, this.end);
}

/// This type is used by [VideoControllerMediaInfo.audioTracks].
class VideoControllerAudioInfo {
  static VideoControllerAudioInfo fromMap(Map map) {
    final format = map['format'] as String?;
    final language = map['language'] as String?;
    final title = map['title'] as String?;
    final bitRate = (map['bitRate'] as num?)?.toInt();
    final channels = (map['channels'] as num?)?.toInt();
    final sampleRate = (map['sampleRate'] as num?)?.toInt();
    return VideoControllerAudioInfo(
      format: format == "" ? null : format,
      language: language == "" ? null : language,
      title: title == "" ? null : title,
      bitRate: bitRate != null && bitRate > 0 ? bitRate : null,
      channels: channels != null && channels > 0 ? channels : null,
      sampleRate: sampleRate != null && sampleRate > 0 ? sampleRate : null,
    );
  }

  static Map<String, VideoControllerAudioInfo> batchFromMap(Map map) => map.map(
    (k, v) => MapEntry(k as String, VideoControllerAudioInfo.fromMap(v as Map)),
  );

  final String? format;
  final String? language;
  final String? title;
  final int? bitRate;
  final int? channels;
  final int? sampleRate;
  const VideoControllerAudioInfo({
    this.format,
    this.language,
    this.title,
    this.bitRate,
    this.channels,
    this.sampleRate,
  });
}

/// This type is used by [VideoControllerMediaInfo.subtitleTracks].
class VideoControllerSubtitleInfo {
  static VideoControllerSubtitleInfo fromMap(Map map) {
    final format = map['format'] as String?;
    final language = map['language'] as String?;
    final title = map['title'] as String?;
    return VideoControllerSubtitleInfo(
      format: format == "" ? null : format,
      language: language == "" ? null : language,
      title: title == "" ? null : title,
    );
  }

  static Map<String, VideoControllerSubtitleInfo> batchFromMap(Map map) =>
      map.map(
        (k, v) => MapEntry(
          k as String,
          VideoControllerSubtitleInfo.fromMap(v as Map),
        ),
      );

  final String? format;
  final String? language;
  final String? title;
  const VideoControllerSubtitleInfo({this.format, this.language, this.title});
}

/// This type is used by [VideoControllerInterface.mediaInfo].
/// [duration] == 0 means the media is realtime stream.
/// [audioTracks] and [subtitleTracks] are maps with track id as key.
class VideoControllerMediaInfo {
  final int duration;
  final Map<String, VideoControllerAudioInfo> audioTracks;
  final Map<String, VideoControllerSubtitleInfo> subtitleTracks;
  final String source;
  const VideoControllerMediaInfo(
    this.duration,
    this.audioTracks,
    this.subtitleTracks,
    this.source,
  );
}
