// Responsive layout tests – pump every screen at mobile (360x640) and
// desktop (1280x800) sizes and fail on ANY render overflow / layout error.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:billing_system/models/bill.dart';
import 'package:billing_system/models/bill_item.dart';
import 'package:billing_system/models/customer.dart';
import 'package:billing_system/models/product.dart';
import 'package:billing_system/providers/billing_provider.dart';
import 'package:billing_system/screens/admin_customers_screen.dart';
import 'package:billing_system/screens/admin_dashboard_screen.dart';
import 'package:billing_system/screens/admin_products_screen.dart';
import 'package:billing_system/screens/bill_history_screen.dart';
import 'package:billing_system/screens/company_invoice_screen.dart';
import 'package:billing_system/screens/consolidated_invoice_screen.dart';
import 'package:billing_system/screens/customers_screen.dart';
import 'package:billing_system/screens/dashboard_screen.dart';
import 'package:billing_system/screens/login_screen.dart';
import 'package:billing_system/screens/orders_screen.dart';
import 'package:billing_system/screens/pos_billing_screen.dart';
import 'package:billing_system/screens/products_screen.dart';
import 'package:billing_system/screens/settings_screen.dart';
import 'package:billing_system/screens/stock_out_screen.dart';
import 'package:billing_system/widgets/quantity_dialog.dart';

const _mobile = Size(360, 640);
const _desktop = Size(1280, 800);

final _productA = Product(
  id: 'p1',
  name: 'Aashirvaad Atta 5kg',
  unit: 'PCS',
  price: 245.0,
  mrp: 245.0,
  stock: 50,
  category: 'Flour & Wheat Products',
);
final _productB = Product(
  id: 'p2',
  name: 'Sunflower Oil 1L',
  unit: 'LTR',
  price: 155.0,
  mrp: 155.0,
  stock: 8,
  category: 'Oil',
);

final _sampleBill = Bill(
  billNumber: '2026AUG13A001',
  date: '2026-08-13T10:30:00',
  customerId: 1,
  customerName: 'Kumar Stores',
  customerPhone: '9876543210',
  paymentType: 'Credit',
  salesType: 'Retail',
  through: 'Ramesh',
  area: 'Anthiyur',
  priceList: 'Retail',
  remarks: '',
  items: [
    BillItem(
      productId: 'p1',
      productName: 'Aashirvaad Atta 5kg',
      unit: 'PCS',
      quantity: 3,
      rate: 245.0,
    ),
    BillItem(
      productId: 'p2',
      productName: 'Sunflower Oil 1L',
      unit: 'LTR',
      quantity: 2,
      rate: 155.0,
    ),
  ],
  subtotal: 1045.0,
  gstTotal: 0.0,
  roundOff: 0.0,
  grandTotal: 1045.0,
  gstBreakup: const {},
  itemCount: 2,
);

void main() {
  // Runs `test` for each screen at both breakpoints.
  for (final size in [_mobile, _desktop]) {
    final label = size == _mobile ? 'mobile 360x640' : 'desktop 1280x800';

    testWidgets('DashboardScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const DashboardScreen()));

    testWidgets('AdminDashboardScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const AdminDashboardScreen()));

    testWidgets('ProductsScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const ProductsScreen()));

    testWidgets('CustomersScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const CustomersScreen()));

    testWidgets('BillHistoryScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const BillHistoryScreen()));

    testWidgets('OrdersScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const OrdersScreen()));

    testWidgets('SettingsScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const SettingsScreen()));

    testWidgets('LoginScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const LoginScreen()));

    testWidgets('AdminProductsScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const AdminProductsScreen()));

    testWidgets('AdminCustomersScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const AdminCustomersScreen()));

    testWidgets('StockOutScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const StockOutScreen()));

    testWidgets('PosBillingScreen ($label) has no layout errors', (tester) async {
      final provider = BillingProvider()
        ..setCustomer(const Customer(
          id: 'c1',
          name: 'Kumar Stores',
          phone: '9876543210',
          address: 'Burgur Road, Anthiyur',
          area: 'Anthiyur',
        ))
        ..addProduct(_productA, quantity: 1)
        ..addProduct(_productB, quantity: 2);
      await _pumpScreen(
        tester,
        size,
        ChangeNotifierProvider<BillingProvider>.value(
          value: provider,
          child: const PosBillingScreen(),
        ),
      );
    });

    testWidgets('CompanyInvoiceScreen ($label) has no layout errors',
        (tester) =>
            _pumpScreen(tester, size, CompanyInvoiceScreen(bill: _sampleBill)));

    testWidgets('ConsolidatedInvoiceScreen ($label) has no layout errors',
        (tester) => _pumpScreen(tester, size, const ConsolidatedInvoiceScreen()));
  }

  testWidgets('QuantityDialog fits on small phones (320x568)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    showDialog<void>(
      context: tester.element(find.byType(Scaffold)),
      builder: (_) => const QuantityDialog(initialQuantity: 1),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: 'QuantityDialog overflows at 320px width');
  });

  testWidgets('QuantityDialog fits on regular phones (360x640)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    showDialog<void>(
      context: tester.element(find.byType(Scaffold)),
      builder: (_) => const QuantityDialog(initialQuantity: 1),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: 'QuantityDialog overflows at 360px width');
  });
}

/// Pumps [child] at [size], letting async loads settle, and asserts that no
/// layout error (overflow) was reported.
Future<void> _pumpScreen(
    WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: child));

  // Let the first async load (products/customers/bills) complete.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Let remaining microtasks / post-frame callbacks flush.
  await tester.pump(const Duration(milliseconds: 100));

  expect(tester.takeException(), isNull,
      reason: 'Layout error on ${size.width.toInt()}x${size.height.toInt()}');
}
