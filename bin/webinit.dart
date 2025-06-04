// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:isolate';

void main(List<String> args) async {
  final path = args.isEmpty ? Directory.current.path : args[0];
  final html = File('$path/web/index.html');
  if (!await html.exists()) {
    print(
      'File not found: ${html.path}. Please make sure your project enabled web support.',
    );
  } else {
    final content = await html.readAsString();
    if (!content.contains('VideoViewPlugin.js')) {
      final newContent = content.replaceFirst(
        RegExp(r'(?=</head>)', caseSensitive: false),
        '  <script src="https://shaka-player-demo.appspot.com/dist/shaka-player.compiled.js"></script>\n  <script src="VideoViewPlugin.js"></script>\n',
      );
      await html.writeAsString(newContent);
      print('referenced VideoViewPlugin.js in "${html.path}"');
    }
    final js = 'web/VideoViewPlugin.js';
    final srcUri = await Isolate.resolvePackageUri(
      Uri.parse('package:video_view/'),
    );
    final srcFile = File(
      srcUri!.toFilePath().replaceFirst(RegExp(r'lib/$'), js),
    );
    await srcFile.copy('$path/$js');
    print('copied VideoViewPlugin.js to "$path/web"');
  }
}
