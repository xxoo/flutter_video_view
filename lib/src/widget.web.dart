import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'player.web.dart';

Widget makeWidget(
  VideoController player,
  BoxFit videoFit,
  Color backgroundColor,
) {
  final video = HtmlElementView(
    viewType: 'video_view',
    creationParams: player.id,
    hitTestBehavior: PlatformViewHitTestBehavior.transparent,
  );
  player.setBackgroundColor(backgroundColor);
  if (videoFit != BoxFit.fitHeight && videoFit != BoxFit.fitWidth) {
    player.setVideoFit(videoFit);
    return video;
  } else {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        player.setVideoFit(
          constraints.maxWidth / constraints.maxHeight >
                  player.videoSize.value.width / player.videoSize.value.height
              ? videoFit == BoxFit.fitHeight
                    ? BoxFit.contain
                    : BoxFit.cover
              : videoFit == BoxFit.fitHeight
              ? BoxFit.cover
              : BoxFit.contain,
        );
        return video;
      },
    );
  }
}
