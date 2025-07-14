// This example shows how to avoid "SetState() called during build" error with SetStateAsync mixin.
// Videos are loaded only when they are in view. After scrolling out of view, they are paused.
// After scrolling out of the screen, they may be disposed. Then you'll see they become black.

import 'package:flutter/material.dart';
import 'package:inview_notifier_list/inview_notifier_list.dart';
import 'package:set_state_async/set_state_async.dart';
import 'package:video_view/video_view.dart';
import 'sources.dart';

InViewNotifierList makeVideoList() => InViewNotifierList(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 200),
  isInViewPortCondition:
      (top, bottom, height) => top * 2 <= height && bottom * 2 > height,
  builder: (context, index) => _VideoItem(index),
  itemCount: videoSources.length,
);

class _VideoItem extends StatefulWidget {
  final int index;
  const _VideoItem(this.index);

  @override
  createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> with SetStateAsync {
  VideoController? thisPlayer;
  bool inView = false;

  @override
  build(_) => InViewNotifierWidget(
    id: '${widget.index}',
    child: Container(
      margin:
          widget.index < videoSources.length
              ? const EdgeInsets.only(bottom: 16)
              : null,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoView(
              looping: true,
              onCreated: (player) {
                thisPlayer = player;
                player.mediaInfo.addListener(setStateAsync);
                player.loading.addListener(setStateAsync);
                player.videoSize.addListener(setStateAsync);
                if (inView) {
                  player.open(videoSources[widget.index]);
                  player.play();
                }
              },
            ),
            if (thisPlayer?.mediaInfo.value != null &&
                thisPlayer!.videoSize.value == Size.zero)
              const Text(
                'Audio only',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            if (thisPlayer != null && thisPlayer!.loading.value)
              const CircularProgressIndicator(),
          ],
        ),
      ),
    ),
    builder: (context, isInView, child) {
      inView = isInView;
      if (thisPlayer != null) {
        if (inView) {
          // We should open the video only if it's niehter loading nor opened.
          if (thisPlayer!.mediaInfo.value == null &&
              !thisPlayer!.loading.value) {
            thisPlayer!.open(videoSources[widget.index]);
          }
          thisPlayer!.play();
        } else {
          thisPlayer!.pause();
        }
      }
      return child!;
    },
  );
}
