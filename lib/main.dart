import 'package:flutter/material.dart';

import 'repositories/media_repository.dart';
import 'repositories/native_audio_repository.dart';
import 'repositories/safari_media_repository.dart';
import 'screens/media_screen.dart';
import 'screens/notch_screen.dart';
import 'repositories/browser_media_repository.dart';
import 'repositories/combined_media_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final browsers = BrowserMediaRepository();
  final repository = CombinedMediaRepository(
    SafariMediaRepository(),
    browsers,
    NativeAudioRepository(),
  );
  runApp(HankyeonApp(repository: repository, browsers: browsers));
  browsers.start();
}

class HankyeonApp extends StatelessWidget {
  final MediaRepository repository;
  final BrowserMediaRepository? browsers;
  const HankyeonApp({super.key, required this.repository, this.browsers});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF88C59C),
        brightness: browsers == null ? Brightness.light : Brightness.dark,
      ),
      scaffoldBackgroundColor: browsers == null ? null : Colors.transparent,
      cardTheme: browsers == null
          ? null
          : const CardThemeData(color: Color(0x281F3027), elevation: 0),
      useMaterial3: true,
    ),
    home: browsers == null
        ? MediaScreen(repository: repository)
        : NotchScreen(repository: repository, browsers: browsers!),
  );
}
