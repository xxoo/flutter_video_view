import 'package:flutter/material.dart';
import 'track_selector.dart';
import 'video_list.dart';
import 'video_player.dart';

void main() => runApp(const MaterialApp(home: AppView()));

enum AppRoute { trackSelector, videoList, videoPlayer }

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  var _appRoute = AppRoute.values.first;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('video_view advanced example')),
    body: _buildBody(),
    bottomNavigationBar: BottomNavigationBar(
      items: AppRoute.values.map(_buildBottomNavigationBarItem).toList(),
      currentIndex: _appRoute.index,
      onTap: (index) => setState(() => _appRoute = AppRoute.values[index]),
    ),
  );

  Widget _buildBody() {
    switch (_appRoute) {
      case AppRoute.trackSelector:
        return const TrackSelector();
      case AppRoute.videoList:
        return const VideoList();
      case AppRoute.videoPlayer:
        return const VideoPlayer();
    }
  }

  BottomNavigationBarItem _buildBottomNavigationBarItem(AppRoute route) {
    switch (route) {
      case AppRoute.trackSelector:
        return const BottomNavigationBarItem(
          icon: Icon(Icons.track_changes),
          label: 'Track Selector',
        );
      case AppRoute.videoList:
        return const BottomNavigationBarItem(
          icon: Icon(Icons.view_stream),
          label: 'Video List',
        );
      case AppRoute.videoPlayer:
        return const BottomNavigationBarItem(
          icon: Icon(Icons.smart_display),
          label: 'Video Player',
        );
    }
  }
}
