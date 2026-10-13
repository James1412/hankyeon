import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/main.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/models/media_snapshot.dart';
import 'package:hankyeon/repositories/media_repository.dart';

import 'media_test_support.dart';

void main() {
  testWidgets('shows real snapshots and routes a button to its own media', (
    tester,
  ) async {
    final repository = FakeMediaRepository();
    await tester.pumpWidget(HankyeonApp(repository: repository));
    repository.send([
      MediaInfo.fromMap(mediaMap()),
      MediaInfo.fromMap(mediaMap(id: 'b', title: '영상 B')),
    ]);
    await tester.pump();
    expect(find.text('영상 A'), findsOneWidget);
    expect(find.text('영상 B'), findsOneWidget);
    await tester.tap(find.byTooltip('일시정지').first);
    await tester.pump();
    expect(repository.commands.single['id'], 'a');
    expect(repository.commands.single['action'], MediaAction.pause);
    repository.send([MediaInfo.fromMap(mediaMap(id: 'b', title: '영상 B'))]);
    await tester.pump();
    expect(find.text('영상 A'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await repository.events.close();
  });

  testWidgets(
    'last snapshot stays visible but disconnected controls are disabled',
    (tester) async {
      final repository = FakeMediaRepository();
      await tester.pumpWidget(HankyeonApp(repository: repository));
      repository.send([
        MediaInfo.fromMap(mediaMap()),
      ], connection: MediaConnection.unavailable);
      await tester.pump();
      expect(find.text('영상 A'), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '일시정지',
        ),
      );
      expect(button.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.events.close();
    },
  );
}
