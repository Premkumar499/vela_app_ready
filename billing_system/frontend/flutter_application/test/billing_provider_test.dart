import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:billing_system/models/product.dart';
import 'package:billing_system/providers/billing_provider.dart';
import 'package:billing_system/services/api_service.dart';

void main() {
  group('BillingProvider Sequential Click Queue Tests', () {
    late BillingProvider provider;
    late Product testProduct;

    setUp(() {
      provider = BillingProvider();
      testProduct = Product(
        id: 'prod-123',
        name: 'Test Product',
        unit: 'pcs',
        price: 10.0,
        mrp: 10.0,
        stock: 100.0,
        category: 'Test Category',
      );
    });

    tearDown(() {
      ApiService.client = http.Client();
    });

    test('Concurrent addProductWithReservation calls are executed sequentially (no overlap)', () async {
      int activeApiRequests = 0;
      bool overlapped = false;
      List<int> executionOrder = [];

      ApiService.client = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/drafts/create')) {
          return http.Response('{"success": true}', 200);
        } else if (path.endsWith('/hold')) {
          activeApiRequests++;
          if (activeApiRequests > 1) {
            overlapped = true;
          }
          // Simulate some server latency
          await Future.delayed(const Duration(milliseconds: 50));
          executionOrder.add(1);
          activeApiRequests--;
          return http.Response(
            '{"success": true, "reservation_id": "res-123", "remaining_available": 90.0}',
            200,
          );
        } else if (path.endsWith('/update-hold')) {
          activeApiRequests++;
          if (activeApiRequests > 1) {
            overlapped = true;
          }
          // Simulate some server latency
          await Future.delayed(const Duration(milliseconds: 50));
          executionOrder.add(2);
          activeApiRequests--;
          return http.Response(
            '{"success": true, "reservation_id": "res-123", "remaining_available": 90.0}',
            200,
          );
        }
        return http.Response('{}', 400);
      });

      // Fire 3 concurrent operations
      final Future<ReservationResult> future1 = provider.addProductWithReservation(testProduct, quantity: 1);
      final Future<ReservationResult> future2 = provider.addProductWithReservation(testProduct, quantity: 1);
      final Future<ReservationResult> future3 = provider.addProductWithReservation(testProduct, quantity: 1);

      // Wait for all to complete
      final results = await Future.wait([future1, future2, future3]);

      // Assertions
      expect(overlapped, isFalse, reason: 'API requests should not overlap concurrently');
      expect(executionOrder.length, equals(3), reason: 'All 3 calls should execute');
      expect(results.every((r) => r.success), isTrue, reason: 'All operations should succeed');
      expect(provider.items.length, equals(1));
      expect(provider.items[0].quantity, equals(3.0));
    });
  });
}
