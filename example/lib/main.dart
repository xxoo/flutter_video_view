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
            'https://stream.mux.com/v69RSHhFelSm4701snP22dYz2jICy4E4FUyk02rW4gxRM.m3u8',
        autoPlay: true,
        looping: true,
        keepScreenOn: true,
        cancelableNotification: true,
        onCreated: (player) => player.loading.addListener(
          () => setState(() => _loading = player.loading.value),
        ),
      ),
      if (_loading) const CircularProgressIndicator(),
    ],
  );
}
