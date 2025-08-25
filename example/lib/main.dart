// This example shows how to play a video from a URL with VideoView widget.
// Which is a very basic way to use video_view package.
// For more advanced usage, see main_advanced.dart.

import 'package:flutter/material.dart';
import 'package:video_view/video_view.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var _loading = true;

  @override
  build(_) => Stack(
    alignment: Alignment.center,
    children: [
      VideoView(
        source:
            'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8',
        autoPlay: true,
        looping: true,
        cancelableNotification: true,
        onCreated: (player) => player.loading.addListener(
          () => setState(() => _loading = player.loading.value),
        ),
      ),
      if (_loading) const CircularProgressIndicator(),
    ],
  );
}
