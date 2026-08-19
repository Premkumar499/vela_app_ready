import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_system/providers/billing_provider.dart';
import 'package:billing_system/screens/login_screen.dart';
import 'package:billing_system/services/api_service.dart';

Widget _wrap(Widget child) => MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => BillingProvider())],
      child: MaterialApp(
        routes: {
          '/dashboard': (_) => const Scaffold(body: Text('Dashboard')),
        },
        home: child,
      ),
    );

void main() {
  group('LoginScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ApiService.client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final mobile = body['mobile_number'] as String?;
          if (mobile == '1234567890') {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'id': 'user-123',
                  'name': 'Test User',
                  'mobile_number': '1234567890',
                  'role_id': 3, // Billing Employee
                }
              }),
              200,
            );
          } else {
            return http.Response(
              jsonEncode({
                'success': false,
                'message': 'Invalid credentials',
              }),
              401,
            );
          }
        }
        return http.Response('Not Found', 404);
      });
    });

    tearDown(() {
      ApiService.client = http.Client();
    });

    testWidgets('shows mobile field and login button', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('shows error on wrong mobile number', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.enterText(find.byType(TextField), '9999999999');
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid credentials'), findsOneWidget);
    });

    testWidgets('navigates to dashboard on correct mobile number', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.enterText(find.byType(TextField), '1234567890');
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('empty mobile number shows local validation error', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.tap(find.text('Login'));
      await tester.pump();
      expect(find.text('Enter your mobile number'), findsOneWidget);
    });
  });
}
