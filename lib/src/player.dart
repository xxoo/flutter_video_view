import 'package:flutter/material.dart';
import 'package:async_value_notifier/async_value_notifier.dart';
import 'player.native.dart' if (dart.library.js_interop) 'player.web.dart';

/// This type is used by [VideoController.displayMode].
enum VideoControllerDisplayMode { normal, fullscreen, pictureInPicture }

/// This type is used by [VideoController.playbackState].
enum VideoControllerPlaybackState { closed, paused, playing }

/// This class is used by [VideoController] to notify listeners when
/// property changes. The [value] setter is protected, you may see warnings
/// when trying to assign value to it.
class VideoControllerProperty<T> extends AsyncValueNotifier<T> {
  VideoControllerProperty(super.value, {super.cancelable, super.distinct});

  @protected
  @override
  set value(T newValue) => super.value = newValue;
}

/// This type is used by [VideoController.bufferRange].
class VideoControllerBufferRange {
  static const empty = VideoControllerBufferRange(0, 0);

  final int start;
  final int end;
  const VideoControllerBufferRange(this.start, this.end);
}

/// This type is used by [VideoControllerMediaInfo.audioTracks].
class VideoControllerAudioInfo {
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

  factory VideoControllerAudioInfo.fromMap(Map map) {
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
}

/// This type is used by [VideoControllerMediaInfo.subtitleTracks].
class VideoControllerSubtitleInfo {
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

  factory VideoControllerSubtitleInfo.fromMap(Map map) {
    final format = map['format'] as String?;
    final language = map['language'] as String?;
    final title = map['title'] as String?;
    return VideoControllerSubtitleInfo(
      format: format == "" ? null : format,
      language: language == "" ? null : language,
      title: title == "" ? null : title,
    );
  }
}

/// This type is used by [VideoController.mediaInfo].
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

/// The interface for creating and controling player instance.
///
/// Do NOT modify properties directly, use the corresponding methods instead.
abstract class VideoController {
  /// This constructor is used by implementations and should be considered as private.
  VideoController.create();

  /// All parameters are optional, and can be changed later by calling the corresponding methods.
  ///
  /// [cancelableNotification] determines whether properties should suppress unchanged notifications.
  /// [distinctNotification] determines whether properties should ignore duplicate listeners.
  /// These behaviors can be controlled independently for each property or globally by calling [setCancelableNotification] or [setDistinctNotification].
  factory VideoController({
    String? source,
    double? volume,
    double? speed,
    bool? looping,
    bool? autoPlay,
    int? position,
    bool? showSubtitle,
    String? preferredSubtitleLanguage,
    String? preferredAudioLanguage,
    int? maxBitRate,
    Size? maxResolution,
    bool? cancelableNotification,
    bool? distinctNotification,
  }) {
    final self = VideoControllerImplementation();
    self.initialize(
      source: source,
      volume: volume,
      speed: speed,
      looping: looping,
      autoPlay: autoPlay,
      position: position,
      showSubtitle: showSubtitle,
      preferredSubtitleLanguage: preferredSubtitleLanguage,
      preferredAudioLanguage: preferredAudioLanguage,
      maxBitRate: maxBitRate,
      maxResolution: maxResolution,
      cancelableNotification: cancelableNotification,
      distinctNotification: distinctNotification,
    );
    return self;
  }

  /// The information of the current media.
  /// It's null before the media is opened.
  final mediaInfo = VideoControllerProperty<VideoControllerMediaInfo?>(null);

  /// The size of the current video.
  /// This value is Size.zero by default, and may change during playback.
  final videoSize = VideoControllerProperty(Size.zero);

  /// The error message of the player.
  /// It's null before an error occurs.
  final error = VideoControllerProperty<String?>(null);

  /// The loading state of the player.
  /// It's false before opening a media.
  final loading = VideoControllerProperty(false);

  /// The playback state of the player.
  /// It's [VideoControllerPlaybackState.closed] berore a media is opened.
  final playbackState = VideoControllerProperty(
    VideoControllerPlaybackState.closed,
  );

  /// The current presentation mode of the video.
  /// The value is always [VideoControllerDisplayMode.normal] on native platforms.
  final displayMode = VideoControllerProperty(
    VideoControllerDisplayMode.normal,
  );

  /// How many times the player has finished playing the current media.
  /// It will be reset to 0 when the media is closed.
  final finishedTimes = VideoControllerProperty(0);

  /// The current buffer status of the player.
  /// It is only reported by network media.
  final bufferRange = VideoControllerProperty(VideoControllerBufferRange.empty);

  /// The audio track that is overrided by the player.
  final overrideAudio = VideoControllerProperty<String?>(null);

  /// The subtitle track that is overrided by the player.
  final overrideSubtitle = VideoControllerProperty<String?>(null);

  /// The position of the current media in milliseconds.
  /// It's 0 before the media is opened.
  final position = VideoControllerProperty(0);

  /// The volume of the player.
  /// It's between 0 and 1, and defaults to 1.
  final volume = VideoControllerProperty(1.0);

  /// The speed of the player.
  /// It's between 0.5 and 2, and defaults to 1.
  final speed = VideoControllerProperty(1.0);

  /// Whether the player should loop the media.
  /// It's false by default.
  final looping = VideoControllerProperty(false);

  /// Whether the player should play the media automatically.
  /// It's false by default.
  final autoPlay = VideoControllerProperty(false);

  /// Current maximum bit rate of the player. 0 means no limit.
  final maxBitRate = VideoControllerProperty(0);

  /// Current maximum resolution of the player. [Size.zero] means no limit.
  final maxResolution = VideoControllerProperty(Size.zero);

  /// The preferred audio language of the player.
  final preferredAudioLanguage = VideoControllerProperty<String?>(null);

  /// The preferred subtitle language of the player.
  final preferredSubtitleLanguage = VideoControllerProperty<String?>(null);

  /// Whether to show subtitles.
  /// By default, the player does not show any subtitle. Regardless of the preferred subtitle language or override tracks.
  final showSubtitle = VideoControllerProperty(false);

  late final _properties = [
    mediaInfo,
    videoSize,
    position,
    error,
    loading,
    playbackState,
    volume,
    speed,
    looping,
    autoPlay,
    finishedTimes,
    bufferRange,
    overrideAudio,
    overrideSubtitle,
    maxBitRate,
    maxResolution,
    preferredAudioLanguage,
    preferredSubtitleLanguage,
    showSubtitle,
    displayMode,
  ];

  /// Whether the player is disposed.
  bool get disposed => _disposed;
  var _disposed = false;

  /// Dispose the player.
  @mustCallSuper
  void dispose() {
    _disposed = true;
    for (final property in _properties) {
      property.dispose();
    }
  }

  /// Update the cancelable notification setting for all properties.
  void setCancelableNotification(bool cancelable) {
    for (final property in _properties) {
      property.cancelable = cancelable;
    }
  }

  /// Update the distinct notification setting for all properties.
  void setDistinctNotification(bool distinct) {
    for (final property in _properties) {
      property.distinct = distinct;
    }
  }

  /// Initialize the player with given parameters.
  void initialize({
    String? source,
    double? volume,
    double? speed,
    bool? looping,
    bool? autoPlay,
    int? position,
    bool? showSubtitle,
    String? preferredSubtitleLanguage,
    String? preferredAudioLanguage,
    int? maxBitRate,
    Size? maxResolution,
    bool? cancelableNotification,
    bool? distinctNotification,
  }) {
    if (cancelableNotification != null) {
      setCancelableNotification(cancelableNotification);
    }
    if (distinctNotification != null) {
      setDistinctNotification(distinctNotification);
    }
    if (source != null) {
      open(source);
      if (position != null) {
        seekTo(position);
      }
    }
    if (volume != null) {
      setVolume(volume);
    }
    if (speed != null) {
      setSpeed(speed);
    }
    if (looping != null) {
      setLooping(looping);
    }
    if (autoPlay != null) {
      setAutoPlay(autoPlay);
    }
    if (maxBitRate != null) {
      setMaxBitRate(maxBitRate);
    }
    if (maxResolution != null) {
      setMaxResolution(maxResolution);
    }
    if (preferredAudioLanguage != null) {
      setPreferredAudioLanguage(preferredAudioLanguage);
    }
    if (preferredSubtitleLanguage != null) {
      setPreferredSubtitleLanguage(preferredSubtitleLanguage);
    }
    if (showSubtitle != null) {
      setShowSubtitle(showSubtitle);
    }
  }

  /// Open a media file.
  ///
  /// [source] is the url or local path of the media file.
  void open(String source);

  /// Close or stop opening the media file.
  void close();

  /// Play the current media.
  ///
  /// If the the player is opening a media file, calling this method will set autoplay to true.
  bool play();

  /// Pause the current media file.
  ///
  /// If the the player is opening a media file, calling this method will set autoplay to false.
  bool pause();

  /// Seek to a specific position.
  ///
  /// [position] is the position to seek to in milliseconds.
  bool seekTo(int position, {bool fast = false});

  /// Set the volume of the player.
  ///
  /// [volume] is the volume to set between 0 and 1.
  bool setVolume(double volume);

  /// Set playback speed of the player.
  ///
  /// [speed] is the speed to set between 0.5 and 2.
  bool setSpeed(double speed);

  /// Set whether the player should loop the media.
  bool setLooping(bool looping);

  /// Set whether the player should play the media automatically.
  bool setAutoPlay(bool autoPlay);

  /// Set the maximum resolution of the player.
  /// This method may not work on windows/safari.
  bool setMaxResolution(Size resolution);

  /// Set the maximum bit rate of the player.
  /// This method may not work on windows/safari.
  bool setMaxBitRate(int bitrate);

  /// Set the preferred audio language of the player. Or use the system default.
  bool setPreferredAudioLanguage(String? language);

  /// Set the preferred subtitle language of the player. Or use the system default.
  bool setPreferredSubtitleLanguage(String? language);

  /// Set whether to show subtitles.
  bool setShowSubtitle(bool show);

  /// Force the player to select an audio track. Or cancel existing override.
  /// [trackId] should be a key of [VideoControllerMediaInfo.audioTracks].
  bool setOverrideAudio(String? trackId);

  /// Force the player to select a subtitle track. Or cancel existing override.
  /// [trackId] should be a key of [VideoControllerMediaInfo.subtitleTracks].
  bool setOverrideSubtitle(String? trackId);

  /// Set video display mode.
  /// This API only works on web.
  bool setDisplayMode(VideoControllerDisplayMode mode);
}
