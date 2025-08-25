import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'player.dart';
import 'player.web.dart';

HtmlElementView makeWidget(
  VideoController player,
  BoxFit videoFit,
  Color backgroundColor,
) {
  (player as VideoControllerImplementation).setStyle(videoFit, backgroundColor);
  return HtmlElementView(
    viewType: 'video_view',
    creationParams: player.id,
    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
  );
}
