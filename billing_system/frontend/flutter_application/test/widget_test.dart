// Basic smoke test – verifies the app boots without throwing.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_system/main.dart';
import 'package:billing_system/services/api_service.dart';

void main() {
  testWidgets('App launches without error', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    ApiService.client = MockClient((request) async {
      if (request.url.path.endsWith('/health')) {
        return http.Response('{"status": "ok"}', 200);
      }
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(const BillingApp());
    expect(find.byType(BillingApp), findsOneWidget);

    // Flush all animations and routes (Splash screen checks health and navigates)
    await tester.pumpAndSettle();

    ApiService.client = http.Client();
  });
}
