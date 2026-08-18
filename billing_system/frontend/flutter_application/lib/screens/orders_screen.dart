import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

/// Orders screen - driven by the salesperson_bills table and completed bills.
///
/// Shows every PENDING submission from the salesmen. Tapping "Generate Bill"
/// pushes the row through create_bill (user bill + company bill + PDFs),
/// then the row disappears from the list.
///
/// Also provides a read-only list of already AUTOMATED/processed orders for reference.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  List<Bill> _automatedBills = [];
  bool _showAutomated = false;
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
    final billsResult = await ApiService.getBills();

    if (!mounted) return;

    if (result.success && billsResult.success) {
      final allBills = billsResult.data ?? [];
      setState(() {
        _orders = result.data ?? [];
        _automatedBills = allBills.where((b) => b.through.isNotEmpty).toList();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result.error ?? billsResult.error;
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

  Future<void> _showUpdatePaymentDialog(Map<String, dynamic> row) async {
    final rowId = row['id']?.toString() ?? '';
    final grandTotal = (row['grand_total'] as num?)?.toDouble() ?? 0.0;
    final currentPaid = (row['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final controller = TextEditingController(text: currentPaid.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Payment Amount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grand Total: \u20B9${grandTotal.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount Paid (\u20B9)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(controller.text);
                if (amount == null || amount < 0 || amount > grandTotal) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please enter a valid amount between 0 and Grand Total'),
                    backgroundColor: AppTheme.error,
                  ));
                  return;
                }
                Navigator.pop(context);
                setState(() => _isLoading = true);
                final res = await ApiService.updateSalespersonBillPayment(rowId, amount);
                if (res.success) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Payment updated successfully'),
                    backgroundColor: AppTheme.success,
                  ));
                  _loadOrders();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(res.error ?? 'Failed to update payment'),
                    backgroundColor: AppTheme.error,
                  ));
                  setState(() => _isLoading = false);
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 20),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Orders',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
      body: Column(
        children: [
          // Segment switcher
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showAutomated = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_showAutomated
                            ? AppTheme.primary
                            : Colors.white,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8)),
                        border: Border.all(
                          color: AppTheme.primary,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Pending Queue (${_orders.length})',
                        style: TextStyle(
                          color: !_showAutomated
                              ? Colors.white
                              : AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showAutomated = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _showAutomated
                            ? AppTheme.primary
                            : Colors.white,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(8)),
                        border: Border.all(
                          color: AppTheme.primary,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'History (${_automatedBills.length})',
                        style: TextStyle(
                          color: _showAutomated
                              ? Colors.white
                              : AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _showAutomated
                        ? (_automatedBills.isEmpty
                            ? _buildEmptyAutomated()
                            : RefreshIndicator(
                                onRefresh: _loadOrders,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _automatedBills.length,
                                  itemBuilder: (_, i) => _AutomatedOrderTile(
                                    bill: _automatedBills[i],
                                  ),
                                ),
                              ))
                        : (_orders.isEmpty
                            ? _buildEmpty()
                            : RefreshIndicator(
                                onRefresh: _loadOrders,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  itemCount: _orders.length,
                                  itemBuilder: (_, i) => _OrderTile(
                                    row: _orders[i],
                                    onGenerate: () => _generateBill(_orders[i]),
                                    onUpdatePayment: () => _showUpdatePaymentDialog(_orders[i]),
                                  ),
                                ),
                              )),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
      ),
    );
  }

  Widget _buildEmptyAutomated() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text('No automated orders yet.', style: AppTheme.headingMedium),
            const SizedBox(height: 8),
            const Text('Processed salesperson bills will appear here.',
                style: AppTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onGenerate;
  final VoidCallback onUpdatePayment;

  const _OrderTile({
    required this.row,
    required this.onGenerate,
    required this.onUpdatePayment,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);
    final salesman = row['submitted_by']?.toString() ?? '';
    final customer = row['customer_name']?.toString() ?? 'Walk-in Customer';
    final payment = row['payment_type']?.toString() ?? 'Cash';
    final grandTotal = (row['grand_total'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (row['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final balance = (row['balance'] as num?)?.toDouble() ?? (grandTotal - amountPaid);
    final createdAt = row['created_at']?.toString() ?? '';
    final rawItems = row['items'] as List<dynamic>? ?? [];
    final items = rawItems.map((e) {
      final m = e as Map<String, dynamic>;
      return '${m['product_name']} x${m['quantity']}';
    }).toList();

    Color paymentBadgeColor;
    String paymentStatusText;
    if (balance <= 0) {
      paymentBadgeColor = AppTheme.success;
      paymentStatusText = 'PAID';
    } else if (amountPaid > 0) {
      paymentBadgeColor = Colors.orange;
      paymentStatusText = 'PARTIALLY PAID';
    } else {
      paymentBadgeColor = AppTheme.error;
      paymentStatusText = 'UNPAID';
    }

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
                    color: (row['status'] == 'ERROR' ? AppTheme.error : AppTheme.info)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    (row['status']?.toString() ?? 'PENDING').toUpperCase(),
                    style: AppTheme.bodySmall.copyWith(
                      color: row['status'] == 'ERROR' ? AppTheme.error : AppTheme.info,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: paymentBadgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    paymentStatusText,
                    style: AppTheme.bodySmall.copyWith(
                      color: paymentBadgeColor,
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
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Paid: ${currency.format(amountPaid)} | Balance: ${currency.format(balance)}',
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: balance > 0 ? AppTheme.error : AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.payment, size: 18),
                    label: const Text('Update Payment'),
                    onPressed: onUpdatePayment,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Generate Bill'),
                    onPressed: onGenerate,
                  ),
                ),
              ],
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

class _AutomatedOrderTile extends StatelessWidget {
  final Bill bill;

  const _AutomatedOrderTile({required this.bill});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);
    final items = bill.items.map((it) => '${it.productName} x${it.quantity % 1 == 0 ? it.quantity.toInt() : it.quantity}').toList();

    final grandTotal = bill.grandTotal;
    final amountPaid = bill.amountPaid;
    final balance = bill.balance;

    Color paymentBadgeColor;
    String paymentStatusText;
    if (balance <= 0) {
      paymentBadgeColor = AppTheme.success;
      paymentStatusText = 'PAID';
    } else if (amountPaid > 0) {
      paymentBadgeColor = Colors.orange;
      paymentStatusText = 'PARTIALLY PAID';
    } else {
      paymentBadgeColor = AppTheme.error;
      paymentStatusText = 'UNPAID';
    }

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
                    color: AppTheme.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'AUTOMATED',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: paymentBadgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    paymentStatusText,
                    style: AppTheme.bodySmall.copyWith(
                      color: paymentBadgeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  bill.billNumber,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  bill.paymentType,
                  style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Salesperson: ${bill.through}',
              style: AppTheme.headingSmall,
            ),
            const SizedBox(height: 2),
            Text(
              'Customer: ${bill.customerName}',
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            ...items.map((it) => Text('• $it', style: AppTheme.bodySmall)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Date: ${_formatDate(bill.date)}',
                  style: AppTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  currency.format(grandTotal),
                  style: AppTheme.headingMedium
                      .copyWith(color: AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Paid: ${currency.format(amountPaid)} | Balance: ${currency.format(balance)}',
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: balance > 0 ? AppTheme.error : AppTheme.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM yyyy  HH:mm').format(dt);
    } catch (_) {
      return dateStr;
    }
  }
}
