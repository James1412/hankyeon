import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/screens/widgets/media_slider.dart';

void main() {
  testWidgets(
    'slider keeps accessibility actions and commits only after release',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var value = 0.5;
      final committed = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: MediaSlider(
                    value: value,
                    min: 0,
                    max: 1,
                    step: 0.05,
                    label: '볼륨',
                    valueText: '${(value * 100).round()}%',
                    onChanged: (next) => setState(() => value = next),
                    onChangeEnd: committed.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final data = tester
          .getSemantics(find.byType(MediaSlider))
          .getSemanticsData();
      expect(data.label, '볼륨');
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      final rect = tester.getRect(find.byType(MediaSlider));
      final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.center.dy),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(committed, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(committed.length, 1);
      expect(committed.single, greaterThan(0.5));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(committed.last, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(committed.last, 0.05);
      semantics.dispose();
    },
  );
}
