// ============================================================
// CONSOLIDATED INVOICE SCREEN
// Shows all bills history as a single consolidated invoice
// ============================================================

import 'package:flutter/material.dart';
import '../models/invoice_model.dart';
import '../services/api_service.dart';
import '../widgets/invoice_preview.dart';

class ConsolidatedInvoiceScreen extends StatefulWidget {
  const ConsolidatedInvoiceScreen({super.key});

  @override
  State<ConsolidatedInvoiceScreen> createState() =>
      _ConsolidatedInvoiceScreenState();
}

class _ConsolidatedInvoiceScreenState extends State<ConsolidatedInvoiceScreen> {
  bool _loading = true;
  Invoice? _consolidatedInvoice;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadConsolidatedInvoice();
  }

  Future<void> _loadConsolidatedInvoice() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final result = await ApiService.getBills();

    if (!mounted) return;

    if (result.success) {
      final bills = result.data ?? [];

      if (bills.isEmpty) {
        setState(() {
          _loading = false;
          _errorMessage = 'No bills found in history';
        });
        return;
      }

      // Aggregate all items from all bills
      final Map<String, InvoiceItem> aggregatedItems = {};

      for (final bill in bills) {
        for (final item in bill.items) {
          final key = '${item.productName}_${item.rate}';

          if (aggregatedItems.containsKey(key)) {
            // Add quantity to existing item
            final existing = aggregatedItems[key]!;
            aggregatedItems[key] = InvoiceItem(
              description: existing.description,
              hsn: existing.hsn,
              unit: existing.unit,
              qty: existing.qty + item.quantity,
              rate: existing.rate,
            );
          } else {
            // Create new item
            aggregatedItems[key] = InvoiceItem(
              description: item.productName,
              hsn: '0000', // HSN not available in current bill data
              unit: item.unit,
              qty: item.quantity,
              rate: item.rate,
            );
          }
        }
      }

      // Calculate date range
      final dates = bills.map((b) => DateTime.parse(b.date)).toList()..sort();
      final startDate = dates.first;
      final endDate = dates.last;

      final dateRange = startDate.day == endDate.day &&
              startDate.month == endDate.month &&
              startDate.year == endDate.year
          ? _formatDate(startDate)
          : '${_formatDate(startDate)} to ${_formatDate(endDate)}';

      // Determine most common payment type
      final paymentTypes = <String, int>{};
      for (final bill in bills) {
        paymentTypes[bill.paymentType] =
            (paymentTypes[bill.paymentType] ?? 0) + 1;
      }
      final mostCommonPayment =
          paymentTypes.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      // Create consolidated invoice
      setState(() {
        _consolidatedInvoice = Invoice(
          invoiceNo: 'CONSOLIDATED',
          invoiceDate: dateRange,
          customerName: 'All Customers',
          customerAddress: 'Consolidated sales report for all transactions',
          customerGstin: 'N/A',
          customerPan: 'N/A',
          paymentMode: mostCommonPayment,
          txnId: 'Multiple transactions',
          upiId: 'N/A',
          items: aggregatedItems.values.toList(),
        );
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
        _errorMessage = result.error ?? 'Failed to load bills';
      });
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consolidated Invoice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadConsolidatedInvoice,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade600)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadConsolidatedInvoice,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _consolidatedInvoice == null
                  ? const Center(child: Text('No data available'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final preview =
                            InvoicePreview(invoice: _consolidatedInvoice!);
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: constraints.maxWidth < 700
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(width: 700, child: preview),
                                )
                              : Center(child: preview),
                        );
                      },
                    ),
    );
  }
}
