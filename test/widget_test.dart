import 'package:flutter_test/flutter_test.dart';
import 'package:hankyeon/main.dart';

void main() {
  testWidgets('Process practice screen renders', (tester) async {
    await tester.pumpWidget(const HankyeonApp());
  });
}
