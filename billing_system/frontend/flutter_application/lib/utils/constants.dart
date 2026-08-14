/// Central constants used across the entire application.
/// To point at a different backend, only this file needs to change.
class AppConstants {
  AppConstants._();

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  /// Base URL for the Flask backend.
  /// Defaults to localhost (same machine). Override per deployment with:
  ///   flutter run --dart-define=API_URL=http://192.168.1.100:5000
  /// (Android emulator uses 10.0.2.2; a physical device needs this machine's LAN IP.)
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:5000',
  );

  static const Duration requestTimeout = Duration(seconds: 15);
  static const Duration connectionTimeout = Duration(seconds: 5);

  // -------------------------------------------------------------------------
  // Error messages
  // -------------------------------------------------------------------------
  static const String errNoConnection =
      'Cannot reach server. Check your network and ensure the backend is running.';
  static const String errServer = 'Server error. Please try again.';
  static const String errValidation = 'Please fill all required fields.';

  // -------------------------------------------------------------------------
  // Route names
  // -------------------------------------------------------------------------
  static const String routeSplash = '/';
  static const String routeLogin = '/login';
  static const String routeDashboard = '/dashboard';
  static const String routeAdminDashboard = '/admin';
  static const String routeAdminProducts = '/admin/products';
  static const String routeAdminCustomers = '/admin/customers';
  static const String routeBilling = '/billing';
  static const String routeProducts = '/products';
  static const String routeCustomers = '/customers';
  static const String routeHistory = '/history';
  static const String routeOrders = '/orders';
  static const String routeBillDetails = '/bill-details';
  static const String routeSettings = '/settings';
  static const String routeStockOut = '/stock-out';

  // -------------------------------------------------------------------------
  // Payment types
  // -------------------------------------------------------------------------
  static const List<String> paymentTypes = ['Cash', 'Credit', 'UPI'];

  // -------------------------------------------------------------------------
  // Sales types
  // -------------------------------------------------------------------------
  static const List<String> salesTypes = ['Retail', 'Wholesale', 'Credit'];

  // -------------------------------------------------------------------------
  // Price lists
  // -------------------------------------------------------------------------
  static const List<String> priceLists = ['Retail', 'Wholesale', 'MRP'];

  // -------------------------------------------------------------------------
  // GST slabs
  // -------------------------------------------------------------------------
  static const List<double> gstSlabs = [0, 5, 12, 18, 28];

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------
  static const double defaultPadding = 12.0;
  static const double cardRadius = 8.0;
  static const double tableRowHeight = 44.0;
}
