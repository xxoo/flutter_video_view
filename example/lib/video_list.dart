// This example turns out the lifecycle of an auto created VideoController is tied to its owner VideoView.
// Videos are loaded only when they are in view. After scrolling out of view, they are paused.
// After scrolling out of the screen, they may be disposed. Then you'll see they become black.

import 'package:flutter/material.dart';
import 'package:inview_notifier_list/inview_notifier_list.dart';
import 'package:video_view/video_view.dart';
import 'sources.dart';

InViewNotifierList makeVideoList() => InViewNotifierList(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 200),
  isInViewPortCondition: (top, bottom, height) =>
      top * 2 <= height && bottom * 2 > height,
  builder: (_, index) => _VideoItem(index),
  itemCount: videoSources.length,
);

class _VideoItem extends StatefulWidget {
  final int index;
  const _VideoItem(this.index);

  @override
  createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  VideoController? _player;
  var _inView = false;

  void _update() => setState(() {});

  @override
  build(_) => InViewNotifierWidget(
    id: '${widget.index}',
    child: Container(
      margin: widget.index < videoSources.length
          ? const .only(bottom: 16)
          : null,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          alignment: .center,
          children: [
            VideoView(
              looping: true,
              cancelableNotification: true,
              onCreated: (player) {
                _player = player;
                player.mediaInfo.addListener(_update);
                player.loading.addListener(_update);
                player.videoSize.addListener(_update);
                if (_inView) {
                  player.open(videoSources[widget.index]);
                  player.play();
                }
              },
            ),
            if (_player?.mediaInfo.value != null &&
                _player!.videoSize.value == .zero)
              const Text(
                'Audio only',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            if (_player != null && _player!.loading.value)
              const CircularProgressIndicator(),
          ],
        ),
      ),
    ),
    builder: (_, isInView, child) {
      _inView = isInView;
      if (_player != null) {
        if (_inView) {
          // We should open the video only if it's niehter loading nor opened.
          if (_player!.mediaInfo.value == null && !_player!.loading.value) {
            _player!.open(videoSources[widget.index]);
          }
          _player!.play();
        } else {
          _player!.pause();
        }
      }
      return child!;
    },
  );
}
