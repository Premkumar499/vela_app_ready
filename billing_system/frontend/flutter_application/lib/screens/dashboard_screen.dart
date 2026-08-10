import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/billing_provider.dart';
import '../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSummary();
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
        title: const Row(
          children: [
            Icon(Icons.point_of_sale, size: 22),
            SizedBox(width: 8),
            Text('ERP Billing System'),
          ],
        ),
        actions: const [],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WelcomeBanner(summary: _summary, loading: _loadingSummary),
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

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature – coming in the next release'),
        backgroundColor: AppTheme.info,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  final Map<String, dynamic> summary;
  final bool loading;

  const _WelcomeBanner({required this.summary, required this.loading});

  @override
  Widget build(BuildContext context) {
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
                  'Welcome Back!',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ERP Billing System · Prototype',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Wrap(
                        spacing: 24,
                        children: [
                          _StatItem(
                            label: 'Bills Today',
                            value: '${summary['total_bills'] ?? 0}',
                          ),
                          _StatItem(
                            label: "Today's Sales",
                            value:
                                '₹${((summary['total_sales'] ?? 0.0) as double).toStringAsFixed(0)}',
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
        childAspectRatio: 1.5,
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
                  style:
                      AppTheme.headingSmall.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
