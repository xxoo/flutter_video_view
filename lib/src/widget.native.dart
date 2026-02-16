import 'package:flutter/widgets.dart';
import 'player.dart';
import 'player.native.dart';
import 'widget.dart';

FittedBox showVideo(VideoController player, VideoView widget) {
  Widget video = Texture(
    textureId: (player as VideoControllerImplementation).id!,
  );
  if (player.orientation % 2 == 1 &&
      player.videoSize.value.height != player.videoSize.value.width) {
    video = OverflowBox(
      maxWidth: player.videoSize.value.height,
      minWidth: player.videoSize.value.height,
      maxHeight: player.videoSize.value.width,
      minHeight: player.videoSize.value.width,
      child: video,
    );
  }
  if (player.orientation > 0) {
    final flip = player.orientation > 3;
    final (a, b, c, d) = switch (player.orientation % 4) {
      1 => (0.0, 1.0, flip ? -1.0 : 1.0, 0.0),
      2 => (flip ? 1.0 : -1.0, 0.0, 0.0, -1.0),
      3 => (0.0, -1.0, flip ? -1.0 : 1.0, 0.0),
      _ => (0.0, 1.0, 1.0, 0.0),
    };
    video = Transform(
      transform: Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1),
      alignment: .center,
      child: video,
    );
  }
  return FittedBox(
    fit: widget.videoFit,
    clipBehavior: .hardEdge,
    child: SizedBox(
      width: player.videoSize.value.width,
      height: player.videoSize.value.height,
      child: player.subId == null || !player.showSubtitle.value
          ? video
          : Stack(
              fit: .passthrough,
              children: [
                video,
                Texture(textureId: player.subId!),
              ],
            ),
    ),
  );
}
