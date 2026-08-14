import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

/// Animated splash screen that checks backend connectivity before proceeding.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  String _statusMessage = 'Initialising…';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();
    _checkBackendAndNavigate();
  }

  Future<void> _checkBackendAndNavigate() async {
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    setState(() => _statusMessage = 'Connecting to server…');

    final isUp = await ApiService.checkHealth();

    if (!mounted) return;

    if (isUp) {
      setState(() => _statusMessage = 'Connected ✓');
      await Future.delayed(const Duration(milliseconds: 600));

      // Auto-login when a saved session exists (Remember me was ticked).
      final session = await SessionService.getSession();
      if (!mounted) return;

      if (session != null) {
        // Admin (role_id 1) → Admin Panel; Billing Employee (role_id 3) → Biller dashboard.
        Navigator.pushReplacementNamed(
            context, SessionService.homeRouteOf(session),
            arguments: session);
      } else {
        Navigator.pushReplacementNamed(context, AppConstants.routeLogin);
      }
    } else {
      setState(() {
        _statusMessage = 'Cannot reach server.\nStarting in offline preview mode…';
        _hasError = true;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppConstants.routeLogin);
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryDark, AppTheme.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ERP Billing System',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Professional POS · Prototype v1.0',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Status
                  if (!_hasError)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  else
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.amberAccent, size: 28),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 60),
                  Text(
                    'Powered by Flask · Flutter',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
