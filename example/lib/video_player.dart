// This example shows how to handle playback events and control the player.
// You can also open an external subtitle file by providing a subtitle URL.
// This functionality is provided by the flutter_subtitle package.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:flutter_subtitle/flutter_subtitle.dart';
import 'package:video_view/video_view.dart';
import 'sources.dart';

class VideoPlayer extends StatefulWidget {
  const VideoPlayer({super.key});

  @override
  createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayer> {
  final _player = VideoController(
    source: videoSources.first,
    cancelableNotification: true,
  );
  final _inputController = TextEditingController();
  SubtitleController? _subtitleController;
  BoxFit _videoFit = .contain;

  void _update() => setState(() {});

  void _setSubtitle(String value) async {
    if (value.isNotEmpty && Uri.tryParse(value) != null) {
      final response = await get(Uri.parse(value));
      setState(
        () => _subtitleController = .string(
          response.body,
          format: value.endsWith('.srt') ? .srt : .webvtt,
        ),
      );
    } else {
      setState(() => _subtitleController = null);
    }
  }

  @override
  initState() {
    super.initState();
    _player.playbackState.addListener(_update);
    _player.position.addListener(_update);
    _player.speed.addListener(_update);
    _player.volume.addListener(_update);
    _player.mediaInfo.addListener(_update);
    _player.videoSize.addListener(_update);
    _player.loading.addListener(_update);
    _player.error.addListener(_update);
    _player.looping.addListener(_update);
    _player.autoPlay.addListener(_update);
    _player.bufferRange.addListener(() {
      if (_player.bufferRange.value != .empty) {
        debugPrint(
          'position: ${_player.position.value} buffer start: ${_player.bufferRange.value.start} buffer end: ${_player.bufferRange.value.end}',
        );
      }
    });
    _player.displayMode.addListener(
      () => debugPrint('Display mode: ${_player.displayMode.value.name}'),
    );
    _inputController.text =
        'https://dash.akamaized.net/akamai/test/caption_test/ElephantsDream/ElephantsDream_en.vtt';
    _setSubtitle(_inputController.text);
  }

  @override
  dispose() {
    //We should dispose this player. cause it's created by us.
    _player.dispose();
    super.dispose();
  }

  @override
  build(_) => SingleChildScrollView(
    child: Column(
      mainAxisSize: .min,
      children: [
        Padding(
          padding: const .all(16),
          child: Column(
            mainAxisSize: .min,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _player.autoPlay.value,
                    onChanged: (value) => _player.setAutoPlay(value ?? false),
                  ),
                  const Text('Autoplay'),
                  const Spacer(),
                  DropdownMenu<BoxFit>(
                    width: 150,
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: .contain, label: "Contain"),
                      DropdownMenuEntry(value: .cover, label: "Cover"),
                      DropdownMenuEntry(value: .fill, label: "Fill"),
                      DropdownMenuEntry(value: .fitWidth, label: "Fill Width"),
                      DropdownMenuEntry(
                        value: .fitHeight,
                        label: "Fill Height",
                      ),
                      DropdownMenuEntry(value: .scaleDown, label: "Scale Down"),
                      DropdownMenuEntry(value: .none, label: "None"),
                    ],
                    label: const Text(
                      "Video Fit",
                      style: TextStyle(fontSize: 14),
                    ),
                    onSelected: (value) {
                      if (value != null) {
                        setState(() => _videoFit = value);
                      }
                    },
                  ),
                  const Spacer(),
                  Checkbox(
                    value: _player.looping.value,
                    onChanged: (value) => _player.setLooping(value ?? false),
                  ),
                  const Text('Looping'),
                ],
              ),
              TextField(
                controller: _inputController,
                decoration: const InputDecoration(
                  labelText: 'Load Subtitle',
                  hintText: 'Please input a subtitle URL',
                ),
                keyboardType: .url,
                onSubmitted: _setSubtitle,
              ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  alignment: .center,
                  children: [
                    VideoView(controller: _player, videoFit: _videoFit),
                    if (_player.mediaInfo.value != null &&
                        _player.videoSize.value == .zero)
                      const Text(
                        'Audio only',
                        style: TextStyle(color: Colors.white, fontSize: 24),
                      ),
                    if (_subtitleController != null)
                      SubtitleControllView(
                        subtitleController: _subtitleController!,
                        inMilliseconds: _player.position.value,
                      ),
                    if (_player.loading.value)
                      const CircularProgressIndicator(),
                  ],
                ),
              ),
              Slider(
                // min: 0,
                max: (_player.mediaInfo.value?.duration ?? 0).toDouble(),
                value: _player.position.value.toDouble(),
                onChanged: (value) => _player.seekTo(value.toInt()),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(_formatTime(_player.position.value)),
                  const Spacer(),
                  Text(
                    _player.error.value ??
                        '${_player.videoSize.value.width.toInt()}x${_player.videoSize.value.height.toInt()}',
                  ),
                  const Spacer(),
                  Text(_formatTime(_player.mediaInfo.value?.duration ?? 0)),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    isSelected: _player.playbackState.value == .playing,
                    selectedIcon: const Icon(Icons.pause),
                    onPressed: () => _player.playbackState.value == .playing
                        ? _player.pause()
                        : _player.play(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: () => _player.close(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.fast_rewind),
                    onPressed: () =>
                        _player.seekTo(_player.position.value - 5000),
                  ),
                  IconButton(
                    icon: const Icon(Icons.fast_forward),
                    onPressed: () =>
                        _player.seekTo(_player.position.value + 5000),
                  ),
                  const Spacer(),
                  Icon(
                    _player.playbackState.value == .playing
                        ? Icons.play_arrow
                        : _player.playbackState.value == .paused
                        ? Icons.pause
                        : Icons.stop,
                    size: 16.0,
                    color: const Color(0x80000000),
                  ),
                  if (kIsWeb) ...[
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.picture_in_picture),
                      onPressed: () => _player.setDisplayMode(
                        _player.displayMode.value == .pictureInPicture
                            ? .normal
                            : .pictureInPicture,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.fullscreen),
                      onPressed: () => _player.setDisplayMode(
                        VideoControllerDisplayMode.fullscreen,
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  Text('Volume: ${_player.volume.value.toStringAsFixed(2)}'),
                  Expanded(
                    child: Slider(
                      value: _player.volume.value,
                      onChanged: (value) => _player.setVolume(value),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('Speed: ${_player.speed.value.toStringAsFixed(2)}'),
                  Expanded(
                    child: Slider(
                      value: _player.speed.value,
                      onChanged: (value) => _player.setSpeed(value),
                      min: 0.5,
                      max: 2,
                      divisions: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: .horizontal,
            padding: const .symmetric(horizontal: 16),
            itemCount: videoSources.length,
            itemBuilder: (_, index) => AspectRatio(
              aspectRatio: 16 / 9,
              child: InkWell(
                onTap: () => _player.open(videoSources[index]),
                child: VideoView(source: videoSources[index]),
              ),
            ),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ),
  );

  String _formatTime(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours > 0 ? '${duration.inHours}:' : '';
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours$minutes:$seconds';
  }
}
