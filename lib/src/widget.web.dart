import 'package:flutter/widgets.dart';
import 'player.dart';
import 'player.web.dart';
import 'widget.dart';

HtmlElementView showVideo(VideoController player, VideoView widget) {
  (player as VideoControllerImplementation).setStyle(
    widget.videoFit,
    widget.backgroundColor,
  );
  return HtmlElementView(
    viewType: 'VideoViewPlugin',
    creationParams: player.id,
    hitTestBehavior: .transparent,
  );
}
