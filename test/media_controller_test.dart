import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/controllers/media_controller.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/models/media_snapshot.dart';
import 'package:hankyeon/repositories/media_repository.dart';

import 'media_test_support.dart';

void main() {
  test(
    'blocks duplicate target commands without blocking other targets',
    () async {
      final repository = FakeMediaRepository()
        ..pendingCommand = Completer<void>();
      final controller = MediaController(repository)..start();
      final a = MediaInfo.fromMap(mediaMap()),
          b = MediaInfo.fromMap(mediaMap(id: 'b'));
      repository.send([a, b]);
      final first = controller.control(a, MediaAction.pause);
      await controller.control(a, MediaAction.play);
      final second = controller.control(b, MediaAction.mute);
      expect(repository.commands.length, 2);
      expect(controller.isBusy(a), isTrue);
      repository.pendingCommand!.complete();
      await Future.wait([first, second]);
      expect(controller.isBusy(a), isFalse);
      controller.dispose();
      await repository.events.close();
    },
  );
  test(
    'rejects stale targets and preserves the last list on stream failure',
    () async {
      final repository = FakeMediaRepository();
      final controller = MediaController(repository)..start();
      final a = MediaInfo.fromMap(mediaMap());
      repository.send([a]);
      repository.events.addError(const FormatException('broken snapshot'));
      expect(controller.snapshot.mediaList.single, a);
      expect(controller.snapshot.connection, MediaConnection.error);
      await controller.control(a, MediaAction.pause);
      expect(repository.commands, isEmpty);
      controller.dispose();
      await repository.events.close();
    },
  );
}
