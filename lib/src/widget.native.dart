import 'package:flutter/widgets.dart';
import 'player.dart';
import 'player.native.dart';

FittedBox makeWidget(VideoController player, BoxFit videoFit, _) {
  final subId = (player as VideoControllerImplementation).subId;
  final video = player.rotation > 0
      ? RotatedBox(
          quarterTurns: player.rotation,
          child: Texture(textureId: player.id!),
        )
      : Texture(textureId: player.id!);
  return FittedBox(
    fit: videoFit,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(
      width: player.videoSize.value.width,
      height: player.videoSize.value.height,
      child: subId == null || !player.showSubtitle.value
          ? video
          : Stack(
              fit: StackFit.passthrough,
              children: [
                video,
                Texture(textureId: subId),
              ],
            ),
    ),
  );
}
