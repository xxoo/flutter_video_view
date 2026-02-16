import 'package:flutter/material.dart';
import 'track_selector.dart';
import 'video_list.dart';
import 'video_player.dart';

void main() => runApp(const MaterialApp(home: AppView()));

enum AppRoute { trackSelector, videoList, videoPlayer }

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  var _appRoute = AppRoute.values.first;

  @override
  build(_) => Scaffold(
    appBar: AppBar(title: const Text('video_view advanced example')),
    body: switch (_appRoute) {
      AppRoute.trackSelector => const TrackSelector(),
      AppRoute.videoList => makeVideoList(),
      AppRoute.videoPlayer => const VideoPlayer(),
    },
    bottomNavigationBar: BottomNavigationBar(
      items: AppRoute.values
          .map(
            (AppRoute route) => switch (route) {
              AppRoute.trackSelector => const BottomNavigationBarItem(
                icon: Icon(Icons.track_changes),
                label: 'Track Selector',
              ),
              AppRoute.videoList => const BottomNavigationBarItem(
                icon: Icon(Icons.view_stream),
                label: 'Video List',
              ),
              AppRoute.videoPlayer => const BottomNavigationBarItem(
                icon: Icon(Icons.smart_display),
                label: 'Video Player',
              ),
            },
          )
          .toList(),
      currentIndex: _appRoute.index,
      onTap: (index) => setState(() => _appRoute = .values[index]),
    ),
  );
}
