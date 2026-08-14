import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// Persists the logged-in user session on the device.
///
/// When the user ticks "Remember me" on the login screen the session is
/// stored permanently, so the app skips login on the next launch. When the
/// checkbox is unticked the session is kept in memory only (lost on restart).
class SessionService {
  SessionService._();

  static const String _keySession = 'login_session';
  static const String _keyRemember = 'remember_me';

  static Map<String, dynamic>? _memorySession;

  /// Save the logged-in user.
  static Future<void> saveSession(Map<String, dynamic> user,
      {bool remember = false}) async {
    _memorySession = user;
    if (remember) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySession, jsonEncode(user));
      await prefs.setBool(_keyRemember, true);
    }
  }

  /// Load the stored session (persisted one first, then in-memory).
  static Future<Map<String, dynamic>?> getSession() async {
    if (_memorySession != null) return _memorySession;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySession);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _memorySession = data;
        return data;
      }
    } catch (_) {}
    return null;
  }

  /// Whether the current session was saved with "Remember me" ticked.
  static Future<bool> isRemembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyRemember) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Extract the role_id from a session map (1 = Admin, 3 = Billing Employee,
  /// 4 = Stock In-Charge).
  static int? roleIdOf(Map<String, dynamic>? session) {
    final role = session?['role_id'];
    return role is num ? role.toInt() : null;
  }

  /// True when the session belongs to an Admin (role_id == 1).
  static bool isAdminSession(Map<String, dynamic>? session) =>
      roleIdOf(session) == 1;

  /// Route the session should land on after login / auto-login.
  static String homeRouteOf(Map<String, dynamic>? session) {
    final role = roleIdOf(session);
    if (role == 1) return AppConstants.routeAdminDashboard;
    if (role == 4) return AppConstants.routeStockOut;
    return AppConstants.routeDashboard;
  }

  /// Clear the session (logout).
  static Future<void> clearSession() async {
    _memorySession = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySession);
      await prefs.remove(_keyRemember);
    } catch (_) {}
  }
}
