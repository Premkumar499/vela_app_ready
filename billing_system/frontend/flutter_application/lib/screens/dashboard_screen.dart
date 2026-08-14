import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/billing_provider.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

/// Main dashboard with navigation tiles and a quick summary row.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _summary = {};
  bool _loadingSummary = true;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final session = await SessionService.getSession();
    if (mounted && session != null) {
      setState(() {
        _userName = session['full_name'] as String? ?? '';
      });
    }
  }

  Future<void> _loadSummary() async {
    // We call the bills/summary endpoint via a raw get; reuse ApiService health
    // check to determine if backend is available, then navigate accordingly.
    final result = await ApiService.getBills();
    if (!mounted) return;
    setState(() {
      if (result.success) {
        final bills = result.data ?? [];
        final today = DateUtils.dateOnly(DateTime.now());
        final todayBills = bills.where((b) {
          final d = DateTime.tryParse(b.date);
          return d != null && DateUtils.isSameDay(d, today);
        }).toList();
        final totalSales = bills.fold<double>(0, (s, b) => s + b.grandTotal);
        final todaySales =
            todayBills.fold<double>(0, (s, b) => s + b.grandTotal);
        _summary = {
          'total_bills': todayBills.length,
          'total_sales': todaySales,
          'all_bills': bills.length,
          'all_sales': totalSales,
        };
      }
      _loadingSummary = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.point_of_sale, size: 22),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'ERP Billing System',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _confirmLogout,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomeBanner(summary: _summary, loading: _loadingSummary, userName: _userName),
              const SizedBox(height: 20),
              const Text('Quick Actions', style: AppTheme.headingLarge),
              const SizedBox(height: 12),
              _ActionGrid(
                tiles: [
                  _DashTile(
                    icon: Icons.add_shopping_cart,
                    label: 'New Bill',
                    subtitle: 'Create a new sale',
                    color: AppTheme.primary,
                    onTap: () {
                      context.read<BillingProvider>().resetBill();
                      Navigator.pushNamed(context, AppConstants.routeBilling);
                    },
                  ),
                  _DashTile(
                    icon: Icons.inventory_2_outlined,
                    label: 'Products',
                    subtitle: 'Browse product catalogue',
                    color: AppTheme.info,
                    onTap: () =>
                        Navigator.pushNamed(context, AppConstants.routeProducts),
                  ),
                  _DashTile(
                    icon: Icons.history,
                    label: 'Bill History',
                    subtitle: 'View past invoices',
                    color: AppTheme.success,
                    onTap: () =>
                        Navigator.pushNamed(context, AppConstants.routeHistory),
                  ),
                  _DashTile(
                    icon: Icons.people_alt_outlined,
                    label: 'Customers',
                    subtitle: 'Manage customer list',
                    color: Colors.deepPurple,
                    onTap: () => Navigator.pushNamed(
                        context, AppConstants.routeCustomers),
                  ),
                  _DashTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Orders',
                    subtitle: 'View & manage orders',
                    color: Colors.orange,
                    onTap: () =>
                        Navigator.pushNamed(context, AppConstants.routeOrders),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppConstants.routeLogin,
      (route) => false,
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  final Map<String, dynamic> summary;
  final bool loading;
  final String userName;

  const _WelcomeBanner({required this.summary, required this.loading, this.userName = ''});

  @override
  Widget build(BuildContext context) {
    final num? all = summary['all_sales'] is num
        ? summary['all_sales'] as num
        : null;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ERP Billing System',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  userName.isNotEmpty ? 'Welcome, $userName' : 'ERP Billing System',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Wrap(
                        spacing: 28,
                        runSpacing: 10,
                        children: [
                          _StatItem(
                            label: 'Total Bills',
                            value: '${summary['all_bills'] ?? 0}',
                          ),
                          _StatItem(
                            label: 'Total Sales',
                            value: '₹${all?.toStringAsFixed(0) ?? '0'}',
                          ),
                        ],
                      ),
              ],
            ),
          ),
          const Icon(Icons.point_of_sale, size: 72, color: Colors.white24),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
      ],
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final List<_DashTile> tiles;

  const _ActionGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 128,
      ),
      itemBuilder: (_, i) => tiles[i],
    );
  }
}

class _DashTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const Spacer(),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTheme.headingSmall.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
