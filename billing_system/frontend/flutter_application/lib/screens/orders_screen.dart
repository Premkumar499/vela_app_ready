import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../utils/theme.dart';

/// Orders screen - driven by the salesperson_bills table.
///
/// Shows every PENDING submission from the salesmen. Tapping "Generate Bill"
/// pushes the row through create_bill (user bill + company bill + PDFs),
/// then the row disappears from the list.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getSalespersonBills();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _orders = result.data ?? [];
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
    }
  }

  Future<void> _generateBill(Map<String, dynamic> row) async {
    final rowId = row['id']?.toString() ?? '';
    if (rowId.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Generating bill...'),
      backgroundColor: AppTheme.info,
    ));

    final result = await ApiService.pushSalespersonBill(rowId);

    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bill ${result.data} created'),
        backgroundColor: AppTheme.success,
      ));
      _loadOrders();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Failed to generate bill'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 20),
            SizedBox(width: 8),
            Text('Orders'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _orders.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadOrders,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _orders.length,
                        itemBuilder: (_, i) => _OrderTile(
                          row: _orders[i],
                          onGenerate: () => _generateBill(_orders[i]),
                        ),
                      ),
                    ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off,
              size: 56, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text('No salesperson orders yet.', style: AppTheme.headingMedium),
          const SizedBox(height: 8),
          const Text('Orders appear here once a salesman submits a bill.',
              style: AppTheme.bodySmall),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onGenerate;

  const _OrderTile({
    required this.row,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);
    final salesman = row['submitted_by']?.toString() ?? '';
    final customer = row['customer_name']?.toString() ?? 'Walk-in Customer';
    final payment = row['payment_type']?.toString() ?? 'Cash';
    final grandTotal = (row['grand_total'] as num?)?.toDouble() ?? 0.0;
    final createdAt = row['created_at']?.toString() ?? '';
    final rawItems = row['items'] as List<dynamic>? ?? [];
    final items = rawItems.map((e) {
      final m = e as Map<String, dynamic>;
      return '${m['product_name']} x${m['quantity']}';
    }).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'PENDING',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.info,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(payment,
                    style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(salesman, style: AppTheme.headingSmall),
            const SizedBox(height: 2),
            Text(customer, style: AppTheme.bodyMedium),
            const SizedBox(height: 6),
            ...items.map((it) => Text('• $it', style: AppTheme.bodySmall)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Submitted: ${_formatDate(createdAt)}',
                    style: AppTheme.bodySmall),
                const Spacer(),
                Text(
                  currency.format(grandTotal),
                  style: AppTheme.headingMedium
                      .copyWith(color: AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Generate Bill'),
                onPressed: onGenerate,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd MMM yyyy  HH:mm').format(dt);
    } catch (_) {
      return isoDate;
    }
  }
}
