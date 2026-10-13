import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/repositories/media_repository.dart';
import 'package:hankyeon/repositories/safari_media_repository.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hankyeon/media/commands');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'control sends complete target identity and clamps seek into valid ranges',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return null;
          });
      final repository = SafariMediaRepository();
      final media = MediaInfo.fromMap(mediaMap());
      await repository.control(media, MediaAction.seek, position: 200);
      expect(received!.method, 'control');
      expect(received!.arguments['tabId'], 12);
      expect(received!.arguments['mediaId'], 'a');
      expect(received!.arguments['position'], 100);
      expect(received!.arguments['tabUrl'], 'https://example.com/watch');
    },
  );
  test('invalid volume never reaches Swift', () {
    final repository = SafariMediaRepository();
    expect(
      () => repository.control(
        MediaInfo.fromMap(mediaMap()),
        MediaAction.volume,
        volume: 2,
      ),
      throwsArgumentError,
    );
  });
}
