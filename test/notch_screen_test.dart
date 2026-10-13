import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/main.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/repositories/browser_media_repository.dart';
import 'package:hankyeon/screens/widgets/media_card.dart';

import 'media_test_support.dart';

class NotchFixture {
  final calls = <MethodCall>[];
  final repository = FakeMediaRepository();
  final browsers = BrowserMediaRepository(port: 0, persistToken: false);
  int get opens => calls
      .where((call) => call.method == 'expand' && call.arguments == true)
      .length;
  int get closes => calls
      .where((call) => call.method == 'expand' && call.arguments == false)
      .length;
}

Future<NotchFixture> mountNotch(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  final fixture = NotchFixture();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('hankyeon/window'), (
        call,
      ) async {
        fixture.calls.add(call);
        if (call.method == 'layout') {
          return {
            'topInset': 32.0,
            'holeWidth': 180.0,
            'normal': false,
            'reduceMotion': reduceMotion,
          };
        }
        return null;
      });
  tester.view.physicalSize = const Size(480, 540);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    HankyeonApp(repository: fixture.repository, browsers: fixture.browsers),
  );
  await tester.pump();
  fixture.repository.send(
    List.generate(
      7,
      (i) => MediaInfo.fromMap(mediaMap(id: '$i', title: '영상 $i')),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await fixture.repository.events.close();
    await fixture.browsers.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hankyeon/window'), null);
  });
  return fixture;
}

Future<void> scrollHeader(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: const Offset(200, 20),
      scrollDelta: Offset(0, delta),
    ),
  );
}

void main() {
  testWidgets(
    'hover previews; swipe opens; pin prevents exit collapse; swipe closes',
    (tester) async {
      final fixture = await mountNotch(tester);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(-1, -1));
      await pointer.moveTo(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(
        fixture.calls.any(
          (call) => call.method == 'hover' && call.arguments == true,
        ),
        isTrue,
      );
      expect(fixture.opens, 0);
      expect(find.byType(MediaCard), findsNothing);
      await scrollHeader(tester, 40);
      await tester.pumpAndSettle();
      expect(fixture.opens, 1);
      expect(find.text('영상 0'), findsOneWidget);
      await tester.tap(find.byTooltip('펼침 고정'));
      await tester.pump();
      await pointer.moveTo(const Offset(-1, -1));
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.closes, 0);
      await pointer.moveTo(const Offset(200, 20));
      await scrollHeader(tester, -40);
      await tester.pumpAndSettle();
      expect(fixture.closes, 1);
      expect(find.byType(MediaCard), findsNothing);
      expect(tester.takeException(), isNull);
      await pointer.removePointer();
    },
  );
  testWidgets(
    'scrolling the media list does not toggle notch and retains its offset',
    (tester) async {
      final fixture = await mountNotch(tester);
      await scrollHeader(tester, 40);
      await tester.pumpAndSettle();
      final finder = find.byKey(const PageStorageKey('notch-media-list'));
      final scroll = tester.widget<ListView>(finder).controller!;
      await tester.drag(finder, const Offset(0, -180));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      expect(fixture.closes, 0);
      await scrollHeader(tester, -40);
      await tester.pumpAndSettle();
      await scrollHeader(tester, 40);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, 1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dragging down opens without click and reduced motion reveals immediately',
    (tester) async {
      final fixture = await mountNotch(tester, reduceMotion: true);
      await tester.drag(
        find.byKey(const ValueKey('notch-handle')),
        const Offset(0, 70),
      );
      await tester.pump();
      expect(fixture.opens, 1);
      expect(find.text('영상 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'idle notch draws no artwork or visible surface and hover only reveals sideways preview',
    (tester) async {
      final fixture = await mountNotch(tester);
      final handle = find.byKey(const ValueKey('notch-handle'));
      tester.view.physicalSize = const Size(185, 32);
      await tester.pump();
      expect(
        find.descendant(of: handle, matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(of: handle, matching: find.byType(Icon)),
        findsNothing,
      );
      final surface = find
          .ancestor(of: handle, matching: find.byType(ColoredBox))
          .first;
      expect(tester.widget<ColoredBox>(surface).color, Colors.transparent);
      expect(tester.getSize(handle).height, 32);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: const Offset(-1, -1));
      await pointer.moveTo(const Offset(92, 16));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: handle, matching: find.byType(Icon)),
        findsWidgets,
      );
      expect(tester.getSize(handle).height, 32);
      expect(fixture.opens, 0);
      for (final width in [185.0, 220.0, 285.0]) {
        tester.view.physicalSize = Size(width, 32);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await pointer.moveTo(const Offset(-1, -1));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: handle, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await pointer.removePointer();
    },
  );
}
