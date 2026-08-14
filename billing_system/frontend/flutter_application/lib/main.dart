import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/bill.dart';
import 'providers/billing_provider.dart';
import 'screens/bill_details_screen.dart';
import 'screens/bill_history_screen.dart';
import 'screens/pos_billing_screen.dart';
import 'screens/company_invoice_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/products_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/stock_out_screen.dart';
import 'screens/consolidated_invoice_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/admin_products_screen.dart';
import 'screens/admin_customers_screen.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Catch Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter Error: ${details.exception}');
    };

    // Provide a fallback UI for widget build errors
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return const Material(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Oops! Something went wrong.\nAn unexpected error occurred in the UI.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.redAccent, fontSize: 16),
            ),
          ),
        ),
      );
    };

    // Lock to landscape on tablets; allow portrait + landscape on phones.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    // Immersive UI – hide status bar on POS screens.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    runApp(const BillingApp());
  }, (error, stack) {
    // Catch asynchronous errors (futures, etc)
    debugPrint('Async Error: $error\n$stack');
  });
}

class BillingApp extends StatelessWidget {
  const BillingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // BillingProvider is the single source of truth for the active bill.
        ChangeNotifierProvider<BillingProvider>(
          create: (_) => BillingProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'ERP Billing System',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeData,

        // ── Initial route ─────────────────────────────────────────────
        initialRoute: AppConstants.routeSplash,

        // ── Named routes ──────────────────────────────────────────────
        routes: {
          AppConstants.routeSplash: (_) => const SplashScreen(),
          AppConstants.routeLogin: (_) => const LoginScreen(),
          AppConstants.routeDashboard: (_) => const DashboardScreen(),
          AppConstants.routeAdminDashboard: (_) =>
              const AdminDashboardScreen(),
          AppConstants.routeAdminProducts: (_) => const AdminProductsScreen(),
          AppConstants.routeAdminCustomers: (_) =>
              const AdminCustomersScreen(),
          AppConstants.routeBilling: (_) => const PosBillingScreen(),
          AppConstants.routeProducts: (_) => const ProductsScreen(),
          AppConstants.routeCustomers: (_) => const CustomersScreen(),
          AppConstants.routeHistory: (_) => const BillHistoryScreen(),
          AppConstants.routeOrders: (_) => const OrdersScreen(),
          AppConstants.routeSettings: (_) => const SettingsScreen(),
          AppConstants.routeStockOut: (_) => const StockOutScreen(),
          '/consolidated-invoice': (_) => const ConsolidatedInvoiceScreen(),
        },

        // BillDetailsScreen receives a billNumber argument so it needs
        // onGenerateRoute rather than a simple routes entry.
        onGenerateRoute: (settings) {
          if (settings.name == AppConstants.routeBillDetails) {
            return MaterialPageRoute(
              builder: (_) => const BillDetailsScreen(),
              settings: settings, // carries the bill_number argument
            );
          }
          
          // Company Invoice Screen
          if (settings.name == '/company_invoice') {
            final bill = settings.arguments as Bill;
            return MaterialPageRoute(
              builder: (_) => CompanyInvoiceScreen(bill: bill),
            );
          }
          
          // Fallback – show dashboard for unknown routes.
          return MaterialPageRoute(
            builder: (_) => const DashboardScreen(),
          );
        },
      ),
    );
  }
}
