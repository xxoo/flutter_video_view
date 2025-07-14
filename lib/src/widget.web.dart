import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'player.web.dart';

HtmlElementView makeWidget(
  VideoController player,
  BoxFit videoFit,
  Color backgroundColor,
) {
  player.setBackgroundColor(backgroundColor);
  player.setVideoFit(videoFit);
  return HtmlElementView(
    viewType: 'video_view',
    creationParams: player.id,
    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
  );
}
