// Basic smoke test for the SFL RM app.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erikshaapp/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('App builds and shows the splash', (WidgetTester tester) async {
    await tester.pumpWidget(const ErikshaApp());
    // Splash renders the SFL wordmark.
    expect(find.text('Satin Finserv Limited'), findsOneWidget);
    // Let the splash timer fire and route onward so no timer stays pending.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}
