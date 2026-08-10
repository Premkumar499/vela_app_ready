/// Central constants used across the entire application.
/// To point at a different backend, only this file needs to change.
class AppConstants {
  AppConstants._();

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  /// Base URL for the Flask backend.
  /// On an Android emulator use 10.0.2.2; on a physical device use your
  /// machine's local IP address (e.g. 192.168.1.100).
  static const String baseUrl = 'http://localhost:5000';

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
  static const String routeBilling = '/billing';
  static const String routeProducts = '/products';
  static const String routeCustomers = '/customers';
  static const String routeHistory = '/history';
  static const String routeOrders = '/orders';
  static const String routeBillDetails = '/bill-details';
  static const String routeSettings = '/settings';

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
