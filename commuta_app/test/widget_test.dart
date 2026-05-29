import 'package:flutter_test/flutter_test.dart';
import 'package:commuta_app/app.dart';

void main() {
  testWidgets('Commuta app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CommutaApp());
    expect(find.byType(CommutaApp), findsOneWidget);
  });
}