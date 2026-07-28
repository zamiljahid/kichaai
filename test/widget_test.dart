import 'package:flutter_test/flutter_test.dart';
import 'package:kichaai/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KichaaiApp());
  });
}
