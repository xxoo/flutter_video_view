import 'package:flutter/widgets.dart';
import 'player.dart';
import 'player.native.dart';

Widget makeWidget(VideoController player, BoxFit videoFit, _) {
  final subId = (player as VideoControllerImplementation).subId;
  final rotation = player.videoRotation.value;

  // Create the video widget with textures
  final videoWidget = subId == null || !player.showSubtitle.value
      ? Texture(textureId: player.id!)
      : Stack(
          fit: StackFit.passthrough,
          children: [
            Texture(textureId: player.id!),
            Texture(textureId: subId),
          ],
        );

  // Apply rotation if needed (for videos with rotation metadata that ExoPlayer doesn't apply)
  final rotatedWidget = rotation != 0
      ? RotatedBox(
          quarterTurns: (rotation ~/ 90) % 4,
          child: videoWidget,
        )
      : videoWidget;

  return FittedBox(
    fit: videoFit,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(
      width: player.videoSize.value.width,
      height: player.videoSize.value.height,
      child: rotatedWidget,
    ),
  );
}
