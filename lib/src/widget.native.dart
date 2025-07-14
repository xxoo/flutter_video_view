import 'package:flutter/widgets.dart';
import 'player.native.dart';

FittedBox makeWidget(VideoController player, BoxFit videoFit, _) => FittedBox(
  fit: videoFit,
  clipBehavior: Clip.hardEdge,
  child: SizedBox(
    width: player.videoSize.value.width,
    height: player.videoSize.value.height,
    child: player.subId == null || !player.showSubtitle.value
        ? Texture(textureId: player.id!)
        : Stack(
            fit: StackFit.passthrough,
            children: [
              Texture(textureId: player.id!),
              Texture(textureId: player.subId!),
            ],
          ),
  ),
);
