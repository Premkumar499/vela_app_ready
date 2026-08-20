import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/product.dart';
import '../models/customer.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../utils/constants.dart';
import 'local_data.dart';

/// Result wrapper – every API call returns either data or an error message
/// without throwing exceptions into the UI layer.
class ApiResult<T> {
  final T? data;
  final String? error;
  final bool success;
  /// True when data came from the local dummy dataset (backend unreachable).
  final bool isOffline;

  const ApiResult.ok(this.data, {this.isOffline = false})
      : error = null,
        success = true;

  const ApiResult.err(this.error)
      : data = null,
        success = false,
        isOffline = false;
}

class ApiService {
  static http.Client client = http.Client();
  static http.Client get _client => client;


  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // -------------------------------------------------------------------------
  // Auth
  // -------------------------------------------------------------------------

  /// Login with mobile_number and optional roleId. Returns user data on success.
  static Future<ApiResult<Map<String, dynamic>>> login(String mobileNumber, {int? roleId}) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/auth/login'),
            headers: _headers,
            body: jsonEncode({
              'mobile_number': mobileNumber,
              if (roleId != null) 'role_id': roleId,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['data'] as Map<String, dynamic>);
      }
      // 401 = wrong credentials
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.err(body['message'] as String? ?? 'Invalid credentials');
      } catch (_) {
        return ApiResult.err('Invalid credentials');
      }
    } catch (_) {
      return const ApiResult.err('Cannot reach server. Check backend is running.');
    }
  }

  // -------------------------------------------------------------------------
  // Health
  // -------------------------------------------------------------------------

  /// Returns true when the backend is reachable.
  static Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('${AppConstants.baseUrl}/health'), headers: _headers)
          .timeout(AppConstants.connectionTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Products
  // -------------------------------------------------------------------------

  /// Fetch all products from the backend; falls back to [LocalData] on failure.
  static Future<ApiResult<List<Product>>> getProducts({
    String? search,
    String? category,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.baseUrl}/products/').replace(
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (category != null && category.isNotEmpty) 'category': category,
        },
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (body['data'] as List<dynamic>)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResult.ok(list);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      // ── Offline fallback ────────────────────────────────────────────────
      var fallback = List<Product>.from(LocalData.products);
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        fallback = fallback
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.category.toLowerCase().contains(q))
            .toList();
      }
      if (category != null && category.isNotEmpty) {
        // Backend filters case-insensitively — keep the offline fallback in sync.
        final q = category.toLowerCase();
        fallback = fallback.where((p) => p.category.toLowerCase() == q).toList();
      }
      return ApiResult.ok(fallback, isOffline: true);
    }
  }

  /// Create a new product in the backend (products + inventory tables).
  static Future<ApiResult<Product>> createProduct({
    required String name,
    required String category,
    required String unit,
    required double price,
    required double stock,
    String sku = '',
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/products/'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'category': category,
              'unit': unit,
              'price': price,
              'stock': stock,
              'sku': sku,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(
            Product.fromJson(body['data'] as Map<String, dynamic>));
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err('Cannot reach server to create product.');
    }
  }

  /// Update an existing product in the backend.
  static Future<ApiResult<Product>> updateProduct(Product product) async {
    try {
      final response = await _client
          .put(
            Uri.parse('${AppConstants.baseUrl}/products/${product.id}'),
            headers: _headers,
            body: jsonEncode({
              'name': product.name,
              'category': product.category,
              'unit': product.unit,
              'price': product.price,
              'stock': product.stock,
              'sku': product.sku,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(
            Product.fromJson(body['data'] as Map<String, dynamic>));
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err('Cannot reach server to update product.');
    }
  }

  /// Delete a product by [productId].
  static Future<ApiResult<String>> deleteProduct(String productId) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('${AppConstants.baseUrl}/products/$productId'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['message'] as String);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err(
          'Cannot delete product: server is unreachable.');
    }
  }

  /// Bulk delete products by [productIds].
  static Future<ApiResult<String>> bulkDeleteProducts(List<String> productIds) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/products/bulk-delete'),
            headers: _headers,
            body: jsonEncode({'product_ids': productIds}),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['message'] as String);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err(
          'Cannot delete products: server is unreachable.');
    }
  }

  // -------------------------------------------------------------------------
  // Customers
  // -------------------------------------------------------------------------

  /// Fetch all customers from the backend; falls back to [LocalData] on failure.
  static Future<ApiResult<List<Customer>>> getCustomers({
    String? search,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.baseUrl}/customers/').replace(
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
        },
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (body['data'] as List<dynamic>)
            .map((e) => Customer.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResult.ok(list);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      // ── Offline fallback ────────────────────────────────────────────────
      var fallback = List<Customer>.from(LocalData.customers);
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        fallback = fallback
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.phone.contains(q) ||
                c.area.toLowerCase().contains(q))
            .toList();
      }
      return ApiResult.ok(fallback, isOffline: true);
    }
  }

  // -------------------------------------------------------------------------
  // Bills
  // -------------------------------------------------------------------------

  /// Submit a new bill to the backend.
  static Future<ApiResult<Map<String, dynamic>>> saveBill({
    required Customer customer,
    required List<BillItem> items,
    required String paymentType,
    String customerPhone = '',
    String salesType = 'Retail',
    String remarks = '',
    String through = '',
    String area = '',
    String priceList = 'Retail',
    String? draftBillId,
  }) async {
    try {
      final body = jsonEncode({
        'customer_id':    customer.id,
        'customer_name':  customer.name,
        'customer_phone': customerPhone,
        'payment_type':   paymentType,
        'sales_type':     salesType,
        'remarks':        remarks,
        'through':        through,
        'area':           area,
        'price_list':     priceList,
        if (draftBillId != null) 'draft_bill_id': draftBillId,
        'items': items.map((e) => e.toJson()).toList(),
      });

      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/bill/'),
            headers: _headers,
            body: body,
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(data);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err(
          'Cannot save bill: server is unreachable. Please start the Flask backend.');
    }
  }

  /// Fetch all saved bills (newest first).
  static Future<ApiResult<List<Bill>>> getBills() async {
    try {
      final response = await _client
          .get(
            Uri.parse('${AppConstants.baseUrl}/bills/'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      return _parseList<Bill>(response, (json) => Bill.fromJson(json));
    } catch (_) {
      // No local bill history — return empty list gracefully
      return ApiResult.ok(<Bill>[], isOffline: true);
    }
  }

  /// Fetch all PENDING salesperson_bills submissions.
  static Future<ApiResult<List<Map<String, dynamic>>>> getSalespersonBills() async {
    try {
      final response = await _client
          .get(
            Uri.parse('${AppConstants.baseUrl}/salesperson-bills/'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (body['data'] as List<dynamic>? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();
        return ApiResult.ok(data);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return ApiResult.err(
          'Cannot reach server to load salesperson bills.');
    }
  }

  /// Push one salesperson_bills row through create_bill.
  /// Generates the user bill + company bill + PDFs, then deletes the row.
  static Future<ApiResult<String>> pushSalespersonBill(String rowId) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/salesperson-bills/$rowId/push'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final billNo = body['bill_number']?.toString() ?? '';
        return ApiResult.ok(billNo);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return ApiResult.err(
          'Cannot push bill: server is unreachable.');
    }
  }

  /// Update the payment amount for a salesperson bill row.
  static Future<ApiResult<Map<String, dynamic>>> updateSalespersonBillPayment(
      String rowId, double amountPaid) async {
    try {
      final response = await _client
          .patch(
            Uri.parse('${AppConstants.baseUrl}/salesperson-bills/$rowId/payment'),
            headers: _headers,
            body: jsonEncode({'amount_paid': amountPaid}),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['data'] as Map<String, dynamic>);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err('Cannot reach server to update payment.');
    }
  }

  /// Update the payment amount for a completed salesperson bill.
  static Future<ApiResult<Map<String, dynamic>>> updateCompletedSalespersonBillPayment(
      String billNo, double amountPaid) async {
    try {
      final response = await _client
          .patch(
            Uri.parse('${AppConstants.baseUrl}/salesperson-bills/completed/$billNo/payment'),
            headers: _headers,
            body: jsonEncode({'amount_paid': amountPaid}),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err('Cannot reach server to update completed payment.');
    }
  }

  /// Fetch a single bill by [billNumber].
  static Future<ApiResult<Bill>> getBillDetails(String billNumber) async {
    try {
      final response = await _client
          .get(
            Uri.parse('${AppConstants.baseUrl}/bills/$billNumber'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(
            Bill.fromJson(body['data'] as Map<String, dynamic>));
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err('Cannot reach server to load bill details.');
    }
  }

  /// Delete a bill by [billNumber].
  static Future<ApiResult<String>> deleteBill(String billNumber) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('${AppConstants.baseUrl}/bills/$billNumber'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['message'] as String);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err(
          'Cannot delete bill: server is unreachable.');
    }
  }

  /// Bulk delete bills by [billNumbers].
  static Future<ApiResult<String>> bulkDeleteBills(List<String> billNumbers) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/bills/bulk-delete'),
            headers: _headers,
            body: jsonEncode({'bill_numbers': billNumbers}),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['message'] as String);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err(
          'Cannot delete bills: server is unreachable.');
    }
  }


  /// Create a new customer in the backend (saves to Supabase).
  static Future<ApiResult<Customer>> createCustomer({
    required String name,
    String phone = '',
    String email = '',
    String address = '',
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/customers/'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'phone': phone,
              'email': email,
              'address': address,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(
            Customer.fromJson(body['data'] as Map<String, dynamic>));
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err('Cannot reach server to create customer.');
    }
  }

  /// Update an existing customer in the backend.
  static Future<ApiResult<Customer>> updateCustomer(Customer customer) async {
    try {
      final response = await _client
          .put(
            Uri.parse('${AppConstants.baseUrl}/customers/${customer.id}'),
            headers: _headers,
            body: jsonEncode({
              'name': customer.name,
              'phone': customer.phone,
              'email': customer.email,
              'address': customer.address,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(
            Customer.fromJson(body['data'] as Map<String, dynamic>));
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err('Cannot reach server to update customer.');
    }
  }

  /// Delete a customer by [customerId].
  static Future<ApiResult<String>> deleteCustomer(String customerId) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('${AppConstants.baseUrl}/customers/$customerId'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['message'] as String);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err(
          'Cannot delete customer: server is unreachable.');
    }
  }

  /// Bulk delete customers by [customerIds].
  static Future<ApiResult<String>> bulkDeleteCustomers(List<String> customerIds) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/customers/bulk-delete'),
            headers: _headers,
            body: jsonEncode({'customer_ids': customerIds}),
          )
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResult.ok(body['message'] as String);
      }
      return ApiResult.err(_extractError(response));
    } catch (_) {
      return const ApiResult.err(
          'Cannot delete customers: server is unreachable.');
    }
  }

  // -------------------------------------------------------------------------
  // Draft Bills (bill_drafts table — shared with GST ERP)
  // -------------------------------------------------------------------------

  /// Create a new ACTIVE row in bill_drafts when a billing session starts.
  /// This anchors all stock reservations to a real DB row instead of a
  /// floating client-generated ID.
  static Future<ApiResult<Map<String, dynamic>>> createDraft({
    required String draftId,
    String? userId,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/drafts/create'),
            headers: _headers,
            body: jsonEncode({
              'draft_id': draftId,
              if (userId != null) 'user_id': userId,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return ApiResult.ok(body);
      }
      // If the draft already exists (network retry), treat as success
      if (body['message']?.toString().contains('already exists') == true) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['message'] as String? ?? 'Could not create draft');
    } catch (_) {
      // Non-fatal — the draft ID is still valid, reservations will link to it
      return const ApiResult.err('Cannot reach server to create draft.');
    }
  }

  /// Mark draft CANCELLED in bill_drafts (bill abandoned).
  static Future<void> cancelDraft(String draftId) async {
    try {
      await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/drafts/cancel'),
            headers: _headers,
            body: jsonEncode({'draft_id': draftId}),
          )
          .timeout(AppConstants.requestTimeout);
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Stock Reservations
  // -------------------------------------------------------------------------

  /// Reserve [quantity] units of [productId] for a draft bill [draftBillId].
  /// Returns the full JSON response from the backend (success, reservation_id,
  /// remaining_available, error_code, message).
  static Future<ApiResult<Map<String, dynamic>>> reserveStock({
    required String productId,
    required String draftBillId,
    required double quantity,
    String? userId,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/reserve'),
            headers: _headers,
            body: jsonEncode({
              'product_id': productId,
              'bill_id':    draftBillId,
              'quantity':   quantity,
              if (userId != null) 'user_id': userId,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['message'] as String? ?? 'Reservation failed');
    } catch (_) {
      return const ApiResult.err('Cannot reach server to reserve stock.');
    }
  }

  /// Release all ACTIVE reservations for [draftBillId] (bill cancelled).
  static Future<ApiResult<Map<String, dynamic>>> releaseBillReservations(
      String draftBillId) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/release-bill'),
            headers: _headers,
            body: jsonEncode({'bill_id': draftBillId}),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResult.ok(body);
    } catch (_) {
      return const ApiResult.err('Cannot reach server to release reservations.');
    }
  }

  /// Complete all ACTIVE reservations for [draftBillId] (bill saved).
  static Future<ApiResult<Map<String, dynamic>>> completeBillReservations(
      String draftBillId) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/complete-bill'),
            headers: _headers,
            body: jsonEncode({'bill_id': draftBillId}),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResult.ok(body);
    } catch (_) {
      return const ApiResult.err('Cannot reach server to complete reservations.');
    }
  }

  /// Expire stale reservations (fire-and-forget housekeeping).
  /// Call this on product list load so stock freed by abandoned drafts
  /// becomes available again without waiting for a cron job.
  static Future<void> expireStaleReservations() async {
    try {
      await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/expire-stale'),
            headers: _headers,
            body: '{}',
          )
          .timeout(AppConstants.requestTimeout);
    } catch (_) {}
  }

  /// Release a single reservation by [reservationId].
  static Future<void> releaseReservation(String reservationId) async {
    try {
      await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/release'),
            headers: _headers,
            body: jsonEncode({'reservation_id': reservationId}),
          )
          .timeout(AppConstants.requestTimeout);
    } catch (_) {}
  }

  /// Atomically update an existing ACTIVE reservation to [newQuantity].
  /// Safer than release + re-reserve: no race window between the two ops.
  /// Returns the full JSON response (success, old_quantity, new_quantity,
  /// remaining_available, error_code, message).
  static Future<ApiResult<Map<String, dynamic>>> updateReservation({
    required String reservationId,
    required double newQuantity,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/update'),
            headers: _headers,
            body: jsonEncode({
              'reservation_id': reservationId,
              'new_quantity':   newQuantity,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['message'] as String? ?? 'Update reservation failed');
    } catch (_) {
      return const ApiResult.err('Cannot reach server to update reservation.');
    }
  }

  // -------------------------------------------------------------------------
  // Stock Holds (migration 0011)
  // Holds reserve stock WITHOUT deducting current_stock. Only the stock-out
  // person's release-hold reduces current_stock (and reserved_stock).
  // -------------------------------------------------------------------------

  /// Hold [quantity] units of [productId] for a draft bill [draftBillId].
  /// current_stock is NOT deducted; only reserved_stock increases.
  /// Returns the full JSON response (success, reservation_id,
  /// remaining_available, error_code, message).
  static Future<ApiResult<Map<String, dynamic>>> holdStock({
    required String productId,
    required String draftBillId,
    required double quantity,
    String? userId,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/hold'),
            headers: _headers,
            body: jsonEncode({
              'product_id': productId,
              'bill_id':    draftBillId,
              'quantity':   quantity,
              if (userId != null) 'user_id': userId,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['message'] as String? ?? 'Hold failed');
    } catch (_) {
      return const ApiResult.err('Cannot reach server to hold stock.');
    }
  }

  /// Stock-out action: release a single hold, deducting current_stock AND
  /// reserved_stock. Returns the error message on failure (e.g.
  /// INSUFFICIENT_STOCK) so the stock-out screen can surface it.
  static Future<ApiResult<Map<String, dynamic>>> releaseHold(
      String reservationId) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/release-hold'),
            headers: _headers,
            body: jsonEncode({'reservation_id': reservationId}),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['message'] as String? ?? 'Release failed');
    } catch (_) {
      return const ApiResult.err('Cannot reach server to release stock.');
    }
  }

  /// Cancel a single hold by [reservationId] (fire-and-forget).
  /// reserved_stock only; current_stock never changes.
  static Future<void> cancelHold(String reservationId) async {
    try {
      await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/cancel-hold'),
            headers: _headers,
            body: jsonEncode({'reservation_id': reservationId}),
          )
          .timeout(AppConstants.requestTimeout);
    } catch (_) {}
  }

  /// Atomically update a HELD reservation to [newQuantity].
  /// Returns the full JSON response (success, old_quantity, new_quantity,
  /// remaining_available, error_code, message).
  static Future<ApiResult<Map<String, dynamic>>> updateHold({
    required String reservationId,
    required double newQuantity,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/update-hold'),
            headers: _headers,
            body: jsonEncode({
              'reservation_id': reservationId,
              'new_quantity':   newQuantity,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['message'] as String? ?? 'Update hold failed');
    } catch (_) {
      return const ApiResult.err('Cannot reach server to update hold.');
    }
  }

  /// Cancel all holds for [billId] (bill cancelled / deleted).
  /// No current_stock change; reserved_stock is freed.
  static Future<ApiResult<Map<String, dynamic>>> cancelBillHolds(
      String billId) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/cancel-bill-holds'),
            headers: _headers,
            body: jsonEncode({'bill_id': billId}),
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ApiResult.ok(body);
    } catch (_) {
      return const ApiResult.err('Cannot reach server to cancel holds.');
    }
  }

  /// Expire stale DRAFT-* holds (fire-and-forget housekeeping).
  /// Only abandoned drafts older than the hold window are cancelled;
  /// real-bill holds never expire.
  static Future<void> expireStaleHolds() async {
    try {
      await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/reservations/expire-stale-holds'),
            headers: _headers,
            body: jsonEncode({'hours': 2}),
          )
          .timeout(AppConstants.requestTimeout);
    } catch (_) {}
  }

  /// Fetch the reserve table: all HELD reservations grouped by bill,
  /// joined with product names and company bill info.
  /// Returns the whole body ({success, count, data}).
  static Future<ApiResult<Map<String, dynamic>>> getHeldReservations() async {
    try {
      final response = await _client
          .get(
            Uri.parse('${AppConstants.baseUrl}/reservations/held'),
            headers: _headers,
          )
          .timeout(AppConstants.requestTimeout);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && body['success'] == true) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['message'] as String? ?? 'Failed to load reserve table');
    } catch (_) {
      return const ApiResult.err('Cannot reach server to load reserve table.');
    }
  }

  // -------------------------------------------------------------------------
  // Warehouse Manager (read-only: product list, barcodes, stock movements)
  // -------------------------------------------------------------------------

  /// Fetch the product list with live stock for the warehouse screen.
  static Future<ApiResult<List<Map<String, dynamic>>>> getWarehouseProducts({
    String? search,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.baseUrl}/warehouse/products')
          .replace(queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(AppConstants.requestTimeout);
      return _parseMapList(response);
    } catch (_) {
      return const ApiResult.err('Cannot reach server to load products.');
    }
  }

  /// Fetch the barcode / SKU list for the warehouse screen.
  static Future<ApiResult<List<Map<String, dynamic>>>> getWarehouseBarcodes({
    String? search,
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.baseUrl}/warehouse/barcodes')
          .replace(queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(AppConstants.requestTimeout);
      return _parseMapList(response);
    } catch (_) {
      return const ApiResult.err('Cannot reach server to load barcodes.');
    }
  }

  /// Fetch the stock in/out movement history for the warehouse screen.
  static Future<ApiResult<List<Map<String, dynamic>>>> getStockMovements({
    String? search,
    int limit = 200,
  }) async {
    try {
      final uri = Uri.parse(
          '${AppConstants.baseUrl}/warehouse/stock-movements').replace(
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          'limit': '$limit',
        },
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(AppConstants.requestTimeout);
      return _parseMapList(response);
    } catch (_) {
      return const ApiResult.err('Cannot reach server to load movements.');
    }
  }

  /// Parse a `{success, data: [...]}` response into a list of maps.
  static ApiResult<List<Map<String, dynamic>>> _parseMapList(
      http.Response response) {
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['data'] as List<dynamic>? ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(_extractError(response));
  }

  /// Translate a list of texts to Tamil (or [target] language) via the backend.  /// Returns originals unchanged if the API key is not configured.
  static Future<List<String>> translateToTamil(List<String> texts,
      {String target = 'ta'}) async {
    if (texts.isEmpty) return texts;
    try {
      final response = await _client
          .post(
            Uri.parse('${AppConstants.baseUrl}/translate/'),
            headers: _headers,
            body: jsonEncode({'texts': texts, 'target': target}),
          )
          .timeout(AppConstants.requestTimeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final list = body['translations'] as List<dynamic>?;
        if (list != null) return list.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return texts; // fall back to originals
  }


  // -------------------------------------------------------------------------

  static ApiResult<List<T>> _parseList<T>(
    http.Response response,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (body['data'] as List<dynamic>)
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(_extractError(response));
  }

  static String _extractError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['message'] as String? ??
          'Unknown error (${response.statusCode})';
    } catch (_) {
      return 'Server error (${response.statusCode})';
    }
  }
}
