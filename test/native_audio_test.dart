import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/models/media_target.dart';
import 'package:hankyeon/repositories/native_audio_repository.dart';
import 'package:hankyeon/repositories/media_repository.dart';
import 'package:hankyeon/screens/widgets/media_card.dart';
import 'package:hankyeon/screens/widgets/media_slider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const discord = MediaInfo(
    target: NativeAppTarget(bundleID: 'com.hnc.Discord', name: 'Discord'),
    title: 'Discord',
    kind: 'appAudio',
  );
  test(
    'native commands cannot reach browser playback or invalid volume',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('hankyeon/audio/commands'),
            (call) async {
              calls.add(call);
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('hankyeon/audio/commands'),
              null,
            ),
      );
      final repo = NativeAudioRepository();
      await repo.control(discord, MediaAction.volume, volume: .4);
      expect(calls.single.arguments, {
        'bundleID': 'com.hnc.Discord',
        'volume': .4,
      });
      await expectLater(
        repo.control(discord, MediaAction.play),
        throwsUnsupportedError,
      );
      await expectLater(
        repo.control(discord, MediaAction.volume, volume: double.nan),
        throwsArgumentError,
      );
      const denied = MediaInfo(
        target: NativeAppTarget(bundleID: 'com.apple.Music', name: 'Music'),
        title: 'Music',
        kind: 'appAudio',
        controlAvailable: false,
      );
      await expectLater(
        repo.control(denied, MediaAction.volume, volume: .2),
        throwsStateError,
      );
      expect(calls, hasLength(1));
    },
  );
  testWidgets('audio-only app has one volume bar and no playback controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: MediaCard(
              media: discord,
              enabled: true,
              busy: false,
              onCommand: (media, action, {volume, position}) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(MediaSlider), findsOneWidget);
    expect(find.byTooltip('재생'), findsNothing);
    expect(find.text('Discord'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
