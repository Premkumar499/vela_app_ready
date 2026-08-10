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
import 'screens/consolidated_invoice_screen.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
          AppConstants.routeBilling: (_) => const PosBillingScreen(),
          AppConstants.routeProducts: (_) => const ProductsScreen(),
          AppConstants.routeCustomers: (_) => const CustomersScreen(),
          AppConstants.routeHistory: (_) => const BillHistoryScreen(),
          AppConstants.routeOrders: (_) => const OrdersScreen(),
          AppConstants.routeSettings: (_) => const SettingsScreen(),
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
