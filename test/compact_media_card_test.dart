import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/models/media_info.dart';
import 'package:hankyeon/screens/widgets/media_card.dart';
import 'package:hankyeon/screens/widgets/marquee_title.dart';
import 'package:hankyeon/screens/widgets/media_slider.dart';

import 'media_test_support.dart';

void main() {
  testWidgets(
    'compact card keeps both controls alongside artwork at narrow widths',
    (tester) async {
      for (final width in [320.0, 420.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: MediaCard(
                    media: MediaInfo.fromMap(mediaMap(title: '짧은 영상')),
                    enabled: true,
                    busy: false,
                    onCommand: (media, action, {volume, position}) async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final sliders = find.byType(MediaSlider);
        expect(sliders, findsNWidgets(2));
        expect(
          tester.getTopLeft(sliders.at(0)).dy,
          tester.getTopLeft(sliders.at(1)).dy,
        );
        expect(tester.getSize(find.byType(MediaCard)).height, lessThan(145));
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'long title moves without duplicate accessible titles; reduced motion is static',
    (tester) async {
      const title =
          'A long media title that cannot possibly fit in the small title viewport';
      Widget host(bool reduced) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: const Center(
            child: SizedBox(width: 140, child: MarqueeTitle(title: title)),
          ),
        ),
      );
      await tester.pumpWidget(host(false));
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<Transform>(find.byType(Transform).last)
            .transform
            .storage[12],
        lessThan(0),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(true));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
