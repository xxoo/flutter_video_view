import 'package:flutter/widgets.dart';
import 'player.dart';
import 'player.native.dart';

FittedBox makeWidget(VideoController player, BoxFit videoFit, _) {
  final subId = (player as VideoControllerImplementation).subId;
  return FittedBox(
    fit: videoFit,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(
      width: player.videoSize.value.width,
      height: player.videoSize.value.height,
      child: subId == null || !player.showSubtitle.value
          ? Texture(textureId: player.id!)
          : Stack(
              fit: StackFit.passthrough,
              children: [
                Texture(textureId: player.id!),
                Texture(textureId: subId),
              ],
            ),
    ),
  );
}
