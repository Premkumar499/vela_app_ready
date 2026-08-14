import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

/// Application settings screen.
/// Displays connection status and configuration options.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checkingServer = false;
  String _serverStatus = 'Not checked';
  bool _serverOk = false;

  Future<void> _checkServer() async {
    setState(() {
      _checkingServer = true;
      _serverStatus = 'Checking…';
    });

    final ok = await ApiService.checkHealth();

    if (!mounted) return;

    setState(() {
      _checkingServer = false;
      _serverOk = ok;
      _serverStatus = ok ? 'Connected ✓' : 'Unreachable ✗';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.settings, size: 20),
            SizedBox(width: 8),
            Text('Settings'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Server connection ──────────────────────────────────────────
          _SettingsSection(
            title: 'Backend Connection',
            icon: Icons.cloud,
            children: [
              _SettingsTile(
                label: 'Server URL',
                value: AppConstants.baseUrl,
                icon: Icons.link,
              ),
              ListTile(
                leading: Icon(
                  _serverOk ? Icons.check_circle : Icons.cancel,
                  color: _serverOk ? AppTheme.success : AppTheme.error,
                ),
                title: const Text('Server Status'),
                subtitle: Text(_serverStatus),
                trailing: _checkingServer
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ElevatedButton(
                        onPressed: _checkServer,
                        child: const Text('Test'),
                      ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'For Android emulator: use 10.0.2.2:5000\n'
                  'For physical device: use your machine\'s local IP (e.g. 192.168.1.x:5000)\n'
                  'Update AppConstants.baseUrl in utils/constants.dart',
                  style: AppTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Billing defaults ───────────────────────────────────────────
          _SettingsSection(
            title: 'Billing Defaults',
            icon: Icons.receipt,
            children: [
              _SettingsTile(
                label: 'Invoice Format',
                value: 'YYYYMMMDDHHmmA (e.g. 2026AUG121325A)',
                icon: Icons.tag,
              ),
              _SettingsTile(
                label: 'Default Payment',
                value: AppConstants.paymentTypes.first,
                icon: Icons.payment,
              ),
              _SettingsTile(
                label: 'Default Price List',
                value: AppConstants.priceLists.first,
                icon: Icons.list_alt,
              ),
              _SettingsTile(
                label: 'GST Slabs',
                value: AppConstants.gstSlabs
                    .map((g) => '${g.toInt()}%')
                    .join(', '),
                icon: Icons.account_balance,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Company info ───────────────────────────────────────────────
          _SettingsSection(
            title: 'Company Information',
            icon: Icons.business,
            children: [
              _SettingsTile(
                  label: 'Company Name', value: 'VELA AGENCY', icon: Icons.store),
              _SettingsTile(
                  label: 'Address',
                  value: 'Burgur Road, Vellai Pillaiyar Kovil, Anthiyur',
                  icon: Icons.location_on),
              _SettingsTile(
                  label: 'Phone',
                  value: '+91 986522355',
                  icon: Icons.phone),
              _SettingsTile(
                  label: 'GSTIN',
                  value: '33BAZPM1155J1ZB',
                  icon: Icons.badge),
            ],
          ),
          const SizedBox(height: 16),

          // ── About ──────────────────────────────────────────────────────
          _SettingsSection(
            title: 'About',
            icon: Icons.info_outline,
            children: [
              _SettingsTile(
                  label: 'Version', value: '1.0.0', icon: Icons.new_releases),
              _SettingsTile(
                  label: 'Stack',
                  value: 'Flutter · Python Flask',
                  icon: Icons.layers),
              _SettingsTile(
                  label: 'Storage',
                  value: 'Supabase PostgreSQL',
                  icon: Icons.cloud_outlined),
              const ListTile(
                leading: Icon(Icons.info, color: AppTheme.info),
                title: Text('About this build'),
                subtitle: Text(
                    'Data is persisted in Supabase. '
                    'Stock reservations are atomic and safe for concurrent access.'),
                isThreeLine: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(title, style: AppTheme.grandTotalLabel),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SettingsTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary, size: 20),
      title: Text(label, style: AppTheme.bodySmall),
      subtitle: Text(value,
          style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
      dense: true,
    );
  }
}
