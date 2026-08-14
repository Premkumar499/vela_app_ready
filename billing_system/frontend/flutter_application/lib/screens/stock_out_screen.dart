import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/theme.dart';

/// Reserve table for the stock-out person.
///
/// Shows all HELD bills (stock reserved at bill time, current_stock NOT
/// reduced). Only the stock-out person can Release an item — that is the
/// single point where current_stock is deducted.
class StockOutScreen extends StatefulWidget {
  const StockOutScreen({super.key});

  @override
  State<StockOutScreen> createState() => _StockOutScreenState();
}

class _StockOutScreenState extends State<StockOutScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _groups = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ApiService.getHeldReservations();
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _loading = false;
        _error = null;
        _groups = List<Map<String, dynamic>>.from(
            (result.data?['data'] as List? ?? const [])
                .cast<Map<String, dynamic>>());
      });
    } else {
      setState(() {
        _loading = false;
        _error = result.error ?? 'Failed to load reserve table';
      });
    }
  }

  Future<void> _releaseOne(String reservationId) async {
    final ok = await _confirm(
      title: 'Release Stock?',
      message: 'Stock out confirms the goods have left. '
          'The quantity will be deducted from stock.',
      actionLabel: 'Release',
    );
    if (ok != true) return;

    final result = await ApiService.releaseHold(reservationId);
    if (!mounted) return;
    if (!result.success) {
      _snack(result.error ?? 'Release failed', error: true);
    } else {
      _snack('Stock released');
    }
    _load();
  }

  Future<void> _releaseBill(Map<String, dynamic> group) async {
    final items = List<Map<String, dynamic>>.from(
        (group['items'] as List? ?? const []).cast<Map<String, dynamic>>());
    final ok = await _confirm(
      title: 'Release Bill ${group['bill_number']}?',
      message: 'Release ${group['total_quantity']} item(s) from stock?',
      actionLabel: 'Release Bill',
    );
    if (ok != true) return;

    var released = 0;
    var failed = 0;
    for (final item in items) {
      final res =
          await ApiService.releaseHold(item['reservation_id'] as String);
      if (res.success) {
        released++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    _snack(failed == 0
        ? 'Released $released item(s)'
        : 'Released $released, failed $failed');
    _load();
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Stock Out — Held Bills',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text('No stock holds'),
            SizedBox(height: 4),
            Text('Bills with held stock will appear here',
                style: AppTheme.bodySmall),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _groups.length,
        itemBuilder: (context, i) {
          final group = _groups[i];
          return _BillGroupCard(
            group: group,
            onReleaseBill: () => _releaseBill(group),
            onReleaseOne: _releaseOne,
          );
        },
      ),
    );
  }
}

class _BillGroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final VoidCallback onReleaseBill;
  final Future<void> Function(String reservationId) onReleaseOne;

  const _BillGroupCard({
    required this.group,
    required this.onReleaseBill,
    required this.onReleaseOne,
  });

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(
        (group['items'] as List? ?? const []).cast<Map<String, dynamic>>());
    final customerName =
        (group['customer_name'] as String? ?? '').trim().isEmpty
            ? 'Draft bill'
            : group['customer_name'] as String;
    final total = (group['total_amount'] as num? ?? 0).toStringAsFixed(2);
    final payment = group['payment_mode'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(
          group['bill_number'] as String? ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(customerName, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              [if (payment.isNotEmpty) payment,
               '${group['total_quantity']} qty',
               '₹$total']
                  .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall,
            ),
          ],
        ),
        trailing: FilledButton.tonal(
          onPressed: onReleaseBill,
          child: const Text('Release Bill'),
        ),
        children: [
          for (final item in items)
            ListTile(
              dense: true,
              title: Text(
                item['name'] as String? ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                'Stock: ${item['current_stock']} (held ${item['reserved_stock']}, '
                'avail ${item['available_stock']})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall,
              ),
              trailing: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${item['quantity']} ${item['unit']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        onReleaseOne(item['reservation_id'] as String),
                    child: const Text('Release'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
