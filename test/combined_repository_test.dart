import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/models/media_target.dart';
import 'package:hankyeon/models/media_snapshot.dart';
import 'package:hankyeon/repositories/combined_media_repository.dart';
import 'package:hankyeon/repositories/media_repository.dart';

import 'media_test_support.dart';

void main() {
  test('browser identity never collides with Safari and commands keep their source', () async {
    final safari = FakeMediaRepository();
    final browser = FakeMediaRepository();
    final repository = CombinedMediaRepository(safari, browser);
    final a = MediaInfo.fromMap(mediaMap());
    final b = MediaInfo.fromMap({
      ...mediaMap(),
      'browserClient': 'client-123',
      'browserName': 'Chrome',
    });
    expect(a.identity, isNot(b.identity));
    await repository.control(b, MediaAction.pause);
    expect(browser.commands.length, 1);
    expect(safari.commands, isEmpty);
    await repository.control(a, MediaAction.pause);
    expect(safari.commands.length, 1);
    await safari.events.close();
    await browser.events.close();
  });
  test(
    'native volume is routed independently and merged without URL identities',
    () async {
      final safari = FakeMediaRepository(),
          browser = FakeMediaRepository(),
          native = FakeMediaRepository();
      final repo = CombinedMediaRepository(safari, browser, native);
      final snapshots = <MediaSnapshot>[];
      final sub = repo.snapshots.listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);
      const app = MediaInfo(
        target: NativeAppTarget(bundleID: 'com.apple.Music', name: 'Music'),
        title: 'Music',
        kind: 'appAudio',
      );
      safari.send([MediaInfo.fromMap(mediaMap())]);
      native.send([app]);
      await Future<void>.delayed(Duration.zero);
      expect(
        snapshots.last.mediaList.map((m) => m.identity),
        contains(app.identity),
      );
      final lateView = await repo.snapshots.first;
      expect(lateView.mediaList.map((m) => m.identity), contains(app.identity));
      await repo.control(app, MediaAction.volume, volume: .25);
      expect(native.commands.single['volume'], .25);
      expect(safari.commands, isEmpty);
      expect(browser.commands, isEmpty);
      await sub.cancel();
      await safari.events.close();
      await browser.events.close();
      await native.events.close();
    },
  );
}
