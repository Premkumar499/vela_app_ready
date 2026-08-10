import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../widgets/bilingual_bill_dashboard.dart';

/// Detailed view of a single saved bill.
/// Receives [billNumber] as a route argument (String).
class BillDetailsScreen extends StatefulWidget {
  const BillDetailsScreen({super.key});

  @override
  State<BillDetailsScreen> createState() => _BillDetailsScreenState();
}

class _BillDetailsScreenState extends State<BillDetailsScreen> {
  Bill? _bill;
  bool _isLoading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final billNumber = ModalRoute.of(context)!.settings.arguments as String;
    _loadBill(billNumber);
  }

  Future<void> _loadBill(String billNumber) async {
    final result = await ApiService.getBillDetails(billNumber);
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _bill = result.data;
      } else {
        _error = result.error;
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_bill != null ? 'Bill – ${_bill!.billNumber}' : 'Bill Details'),
        actions: [
          if (_bill != null)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print',
              onPressed: () {
                final bill = _bill!;
                String formattedDate = '';
                String formattedTime = '';
                try {
                  final dt = DateTime.parse(bill.date);
                  formattedDate = DateFormat('dd/MM/yyyy').format(dt);
                  formattedTime = DateFormat('hh:mm a').format(dt);
                } catch (_) {
                  formattedDate = bill.date;
                  formattedTime = '';
                }

                final receiptData = {
                  'company': {
                    'name': 'VELA AGENCY',
                    'address': 'Anthiyur',
                  },
                  'invoice': {
                    'bill_no': bill.billNumber,
                    'invoice_type': 'NON_GST',
                    'date': formattedDate,
                    'time': formattedTime,
                  },
                  'customer': {
                    'name': bill.customerName,
                  },
                  'items': bill.items.map((item) => {
                    'product_name': item.productName,
                    'brand': '',
                    'qty': item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity,
                    'unit': item.unit,
                    'rate': item.rate.toStringAsFixed(2),
                    'amount': item.total.toStringAsFixed(2),
                  }).toList(),
                  'summary': {
                    'total_qty': bill.items.fold<num>(0, (s, i) => s + (i.quantity % 1 == 0 ? i.quantity.toInt() : i.quantity)),
                    'total': bill.grandTotal.toStringAsFixed(2),
                  },
                  'payment': {
                    'method': bill.paymentType,
                  },
                };

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogCtx) => Dialog(
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
                        child: BilingualBillDashboard(
                          receiptData: receiptData,
                          onClose: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(_error!, style: AppTheme.bodyMedium),
          ],
        ),
      );
    }

    if (_bill == null) return const SizedBox.shrink();

    final bill = _bill!;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final dateStr = _formatDate(bill.date);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bill header card
          _SectionCard(
            title: 'Bill Information',
            icon: Icons.receipt_long,
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _InfoField('Bill Number', bill.billNumber),
                _InfoField('Date', dateStr),
                _InfoField('Customer', bill.customerName),
                _InfoField('Payment', bill.paymentType),
                _InfoField('Sales Type', bill.salesType),
                _InfoField('Price List', bill.priceList),
                if (bill.area.isNotEmpty) _InfoField('Area', bill.area),
                if (bill.through.isNotEmpty) _InfoField('Through', bill.through),
                if (bill.remarks.isNotEmpty) _InfoField('Remarks', bill.remarks),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Items table
          _SectionCard(
            title: 'Items (${bill.items.length})',
            icon: Icons.inventory_2_outlined,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 40,
                columnSpacing: 16,
                horizontalMargin: 8,
                border: TableBorder(
                  horizontalInside: BorderSide(color: AppTheme.divider),
                ),
                columns: const [
                  DataColumn(label: Text('S.No', style: AppTheme.tableHeaderStyle)),
                  DataColumn(label: Text('Item', style: AppTheme.tableHeaderStyle)),
                  DataColumn(label: Text('Unit', style: AppTheme.tableHeaderStyle)),
                  DataColumn(label: Text('Qty', style: AppTheme.tableHeaderStyle)),
                  DataColumn(label: Text('Rate', style: AppTheme.tableHeaderStyle)),
                  DataColumn(label: Text('GST%', style: AppTheme.tableHeaderStyle)),
                  DataColumn(label: Text('GST Amt', style: AppTheme.tableHeaderStyle)),
                  DataColumn(label: Text('Total', style: AppTheme.tableHeaderStyle)),
                ],
                rows: bill.items.asMap().entries.map((e) {
                  final i = e.key;
                  final item = e.value;
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(SizedBox(
                      width: 140,
                      child: Text(item.productName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(item.unit)),
                    DataCell(Text(item.quantity.toStringAsFixed(2))),
                    DataCell(Text(currency.format(item.rate))),
                    DataCell(Text('${item.gstPercent.toInt()}%')),
                    DataCell(Text(currency.format(item.gstAmount))),
                    DataCell(Text(
                      currency.format(item.total),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppTheme.primary),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Totals + GST breakup side by side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Totals
              Expanded(
                child: _SectionCard(
                  title: 'Summary',
                  icon: Icons.calculate,
                  child: Column(
                    children: [
                      _TotalRow('Subtotal', currency.format(bill.subtotal)),
                      _TotalRow('Total GST', currency.format(bill.gstTotal),
                          color: AppTheme.success),
                      _TotalRow('Round Off',
                          '${bill.roundOff >= 0 ? "+" : ""}${currency.format(bill.roundOff)}',
                          color: AppTheme.textSecondary),
                      const Divider(),
                      _TotalRow(
                        'Grand Total',
                        currency.format(bill.grandTotal),
                        isBold: true,
                        color: AppTheme.primary,
                        fontSize: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // GST breakup
              Expanded(
                child: _SectionCard(
                  title: 'GST Breakup',
                  icon: Icons.account_balance,
                  child: Column(
                    children: [
                      ...bill.gstBreakup.entries.map(
                        (e) => _TotalRow(e.key, currency.format(e.value)),
                      ),
                      const Divider(),
                      _TotalRow('Total', currency.format(bill.gstTotal),
                          isBold: true, color: AppTheme.success),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy  HH:mm').format(dt);
    } catch (_) {
      return isoDate;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard(
      {required this.title, required this.icon, required this.child});

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
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  final String label;
  final String value;

  const _InfoField(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value,
              style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? color;
  final double? fontSize;

  const _TotalRow(this.label, this.value,
      {this.isBold = false, this.color, this.fontSize});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize ?? 14,
      fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
      color: color ?? AppTheme.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
