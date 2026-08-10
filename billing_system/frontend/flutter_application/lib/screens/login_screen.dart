import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../utils/constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final mobile = _controller.text.trim();
    if (mobile.isEmpty) {
      setState(() => _error = 'Enter your mobile number');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final result = await ApiService.login(mobile);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      // Navigate and pass user info to dashboard
      Navigator.pushReplacementNamed(
        context,
        AppConstants.routeDashboard,
        arguments: result.data,
      );
    } else {
      setState(() => _error = result.error ?? 'Login failed');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Branding
                  const Icon(Icons.storefront_rounded, size: 56, color: Colors.white),
                  const SizedBox(height: 12),
                  const Text(
                    'ERP Billing System',
                    style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Professional POS Management',
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 36),

                  // Card
                  Card(
                    elevation: 12,
                    shadowColor: Colors.black38,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Welcome back',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary)),
                          const SizedBox(height: 4),
                          const Text('Enter your mobile number to continue',
                              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                          const SizedBox(height: 28),
                          TextField(
                            controller: _controller,
                            obscureText: _obscure,
                            keyboardType: TextInputType.phone,
                            onSubmitted: (_) => _login(),
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              labelText: 'Mobile Number',
                              prefixIcon: const Icon(Icons.phone_android_rounded,
                                  color: AppTheme.primary),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure ? Icons.visibility_off_outlined
                                           : Icons.visibility_outlined,
                                  color: AppTheme.textSecondary,
                                ),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                              errorText: _error,
                              filled: true,
                              fillColor: const Color(0xFFF7F7F7),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                              errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.error, width: 1.5)),
                              focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppTheme.error, width: 2)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5))
                                  : const Text('Login',
                                      style: TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Text(
                    'Powered by Flask · Flutter',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45)),
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
