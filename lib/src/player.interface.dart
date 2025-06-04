import 'package:flutter/material.dart';
import 'player.common.dart';

/// The interface for creating and controling player instance.
///
/// Do NOT modify properties directly, use the corresponding methods instead.
abstract class VideoControllerInterface {
  /// The information of the current media.
  /// It's null before the media is opened.
  final mediaInfo = VideoControllerProperty<VideoControllerMediaInfo?>(null);

  /// The size of the current video.
  /// This value is Size.zero by default, and may change during playback.
  final videoSize = VideoControllerProperty<Size>(Size.zero);

  /// The position of the current media in milliseconds.
  /// It's 0 before the media is opened.
  final position = VideoControllerProperty(0);

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

  /// Indicates whether the player is in fullscreen mode.
  /// This API only works on web.
  final fullscreen = VideoControllerProperty(false);

  /// Indicates whether the player is in picture in picture mode.
  /// This API only works on web.
  final pictureInPicture = VideoControllerProperty(false);

  /// All parameters are optional, and can be changed later by calling the corresponding methods.
  VideoControllerInterface({
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
  }) {
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

  /// Whether the player is disposed.
  bool get disposed;

  /// The id of the player.
  /// It should be unique and never change again after the player is initialized, or null otherwise.
  int? get id;

  /// Dispose the player.
  void dispose();

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

  /// Set whether the player should be fullscreen.
  /// This API only works on web.
  bool setFullscreen(bool value);

  /// Set whether the player should be in picture in picture mode.
  /// This API only works on web.
  bool setPictureInPicture(bool value);
}
