import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../services/api_service.dart';
import '../services/invoice_export_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

/// Bill History with two tabs:
///   1. Cash Bills  – simple bilingual customer receipt
///   2. Company Invoices – professional VELA AGENCY invoice
class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<Bill> _allBills = [];
  List<Bill> _filtered = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBills();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBills() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getBills();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _allBills = result.data!;
        _applyFilter();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allBills.where((b) {
        return query.isEmpty ||
            b.billNumber.toLowerCase().contains(query) ||
            b.customerName.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _deleteBill(String billNumber) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Delete bill $billNumber? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final result = await ApiService.deleteBill(billNumber);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          result.success ? 'Bill $billNumber deleted.' : result.error ?? ''),
      backgroundColor: result.success ? AppTheme.success : AppTheme.error,
    ));

    if (result.success) _loadBills();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.history, size: 20),
            SizedBox(width: 8),
            Text('Bill History'),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by bill number or customer…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white70),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilter();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white24,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.receipt, size: 18),
                    text: 'User Bill',
                  ),
                  Tab(
                    icon: Icon(Icons.business_center, size: 18),
                    text: 'Company Bill',
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBills,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBillList(isCashBill: true),
                    _buildBillList(isCashBill: false),
                  ],
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
              onPressed: _loadBills,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBillList({required bool isCashBill}) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCashBill ? Icons.receipt_long : Icons.business_center,
              size: 64,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _allBills.isEmpty ? 'No bills saved yet.' : 'No results found.',
              style: AppTheme.headingMedium,
            ),
            if (_allBills.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('Create a new bill to see it here.',
                  style: AppTheme.bodySmall),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBills,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _BillTile(
          bill: _filtered[i],
          currency: currency,
          isCashBill: isCashBill,
          onTap: () => Navigator.pushNamed(
            context,
            AppConstants.routeBillDetails,
            arguments: _filtered[i].billNumber,
          ),
          onDelete: () => _deleteBill(_filtered[i].billNumber),
          onView: () {
            if (isCashBill) {
              // Open bilingual cash bill receipt
              _openCashBill(_filtered[i]);
            } else {
              // Open professional company invoice
              Navigator.pushNamed(
                context,
                '/company_invoice',
                arguments: _filtered[i],
              );
            }
          },
        ),
      ),
    );
  }

  void _openCashBill(Bill bill) {
    // Build receipt data map matching BilingualBillDashboard format
    final dt = DateTime.tryParse(bill.date) ?? DateTime.now();
    final receiptData = {
      'invoice': {
        'bill_no': bill.billNumber,
        'date': DateFormat('dd/MM/yyyy').format(dt),
        'time': DateFormat('hh:mm a').format(dt),
      },
      'payment': {
        'method': bill.paymentType,
      },
      'items': bill.items
          .map((item) => {
                'product_name': item.productName,
                'qty': item.quantity,
                'rate': item.rate,
                'amount': item.total,
                'unit': item.unit,
              })
          .toList(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CashBillPreviewScreen(
          receiptData: receiptData,
          billNumber: bill.billNumber,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bill Tile
// ─────────────────────────────────────────────────────────────────────────────

class _BillTile extends StatelessWidget {
  final Bill bill;
  final NumberFormat currency;
  final bool isCashBill;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onView;

  const _BillTile({
    required this.bill,
    required this.currency,
    required this.isCashBill,
    required this.onTap,
    required this.onDelete,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(bill.date);
    final paymentColor = bill.paymentType == 'Cash'
        ? AppTheme.success
        : bill.paymentType == 'Credit'
            ? AppTheme.warning
            : AppTheme.info;

    // Different accent for each section
    final accentColor = isCashBill ? AppTheme.success : AppTheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Bill number badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    bill.billNumber,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Bill info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(bill.billNumber,
                            style: AppTheme.headingSmall
                                .copyWith(color: accentColor)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: paymentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            bill.paymentType,
                            style: AppTheme.bodySmall.copyWith(
                              color: paymentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(bill.customerName, style: AppTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(dateStr, style: AppTheme.bodySmall),
                        const SizedBox(width: 12),
                        const Icon(Icons.inventory_2_outlined,
                            size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text('${bill.itemCount} items',
                            style: AppTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              // Grand total + actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currency.format(bill.grandTotal),
                    style: AppTheme.headingMedium.copyWith(color: accentColor),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // View bill button – different icon per tab
                      IconButton(
                        icon: Icon(
                          isCashBill
                              ? Icons.receipt_long
                              : Icons.business_center,
                          color: accentColor,
                          size: 20,
                        ),
                        onPressed: onView,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip:
                            isCashBill ? 'View Cash Bill' : 'View Company Invoice',
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppTheme.error, size: 20),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Delete',
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right,
                          color: AppTheme.textSecondary),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
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
// Cash Bill Preview Screen (wraps BilingualBillDashboard widget inline)
// ─────────────────────────────────────────────────────────────────────────────

class _CashBillPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> receiptData;
  final String billNumber;

  const _CashBillPreviewScreen({
    required this.receiptData,
    required this.billNumber,
  });

  @override
  State<_CashBillPreviewScreen> createState() =>
      _CashBillPreviewScreenState();
}

class _CashBillPreviewScreenState extends State<_CashBillPreviewScreen> {
  final GlobalKey _billKey = GlobalKey();
  bool _isSaving = false;

  Future<void> _download() async {
    setState(() => _isSaving = true);

    final result = await InvoiceExportService.saveInvoiceAsImage(
      widgetKey: _billKey,
      invoiceNumber: widget.billNumber,
      isCompanyInvoice: false,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result['success'] == true
          ? 'Saved: ${result['bucket'] ?? ''}/${result['fileName'] ?? ''}'
          : result['message']?.toString() ?? 'Failed to save'),
      backgroundColor:
          result['success'] == true ? AppTheme.success : AppTheme.error,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _InlineCashBill(
      receiptData: widget.receiptData,
      billKey: _billKey,
      isSaving: _isSaving,
      onClose: () => Navigator.pop(context),
      onDownload: _download,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline Cash Bill renderer (thermal receipt style)
// ─────────────────────────────────────────────────────────────────────────────

class _InlineCashBill extends StatelessWidget {
  final Map<String, dynamic> receiptData;
  final GlobalKey billKey;
  final bool isSaving;
  final VoidCallback onClose;
  final VoidCallback onDownload;

  const _InlineCashBill({
    required this.receiptData,
    required this.billKey,
    required this.isSaving,
    required this.onClose,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final invoice = (receiptData['invoice'] as Map<String, dynamic>?) ?? {};
    final payment = (receiptData['payment'] as Map<String, dynamic>?) ?? {};
    final rawItems = (receiptData['items'] as List<dynamic>?) ?? [];

    final billNo = invoice['bill_no']?.toString() ?? '';
    final date = invoice['date']?.toString() ?? '';
    final time = invoice['time']?.toString() ?? '';
    final paymentMode =
        payment['method']?.toString().toUpperCase() ?? 'CASH';

    final items = rawItems.map((e) {
      final m = e as Map<String, dynamic>;
      double p(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }

      return {
        'name': m['product_name']?.toString() ?? '',
        'qty': p(m['qty']),
        'rate': p(m['rate']),
        'amount': p(m['amount'] ?? (p(m['qty']) * p(m['rate']))),
        'unit': m['unit']?.toString() ?? '',
      };
    }).toList();

    final totalItems = items.length;
    final totalQty =
        items.fold<double>(0, (s, i) => s + (i['qty'] as double));
    final grandTotal =
        items.fold<double>(0, (s, i) => s + (i['amount'] as double));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: onClose,
        ),
        title: Row(children: [
          const Icon(Icons.receipt_long, color: Colors.greenAccent, size: 22),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Cash Bill',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white)),
            Text('Bill · $billNo',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ]),
        actions: [
          if (isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_alt, color: Colors.white),
              tooltip: 'Save as Image',
              onPressed: onDownload,
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(
            child: RepaintBoundary(
              key: billKey,
              child: Container(
              width: 380,
              decoration: BoxDecoration(
                color: const Color(0xFFF9F6EE),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10)),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  const Center(
                    child: Text('VELA AGENCY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87)),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                        'மளிகை மொத்த மற்றும் சில்லறை\nவியாபாரம்...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                            height: 1.5)),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                        'பர்கூர் ரோடு, வெள்ளை பிள்ளையார்\nகோவில், அந்தியூர்.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                            height: 1.5)),
                  ),
                  const SizedBox(height: 10),
                  _dash('-'),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text('INVOICE / CASH BILL',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Colors.black87)),
                  ),
                  const SizedBox(height: 6),
                  _dash('-'),
                  const SizedBox(height: 10),
                  // Bill meta
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bill No : $billNo',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                            const SizedBox(height: 4),
                            Text('Time    : $time',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                          ]),
                      Text('Date : $date',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _dash('-'),
                  const SizedBox(height: 6),
                  // Table header
                  const Row(children: [
                    SizedBox(
                        width: 28,
                        child: Text('SNo',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87))),
                    Expanded(
                        flex: 4,
                        child: Text('Description / விவரம்',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87))),
                    SizedBox(
                        width: 36,
                        child: Text('Qty',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87))),
                    SizedBox(
                        width: 56,
                        child: Text('Rate',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87))),
                    SizedBox(
                        width: 64,
                        child: Text('Amount',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87))),
                  ]),
                  const SizedBox(height: 6),
                  _dash('-'),
                  const SizedBox(height: 6),
                  // Items
                  ...List.generate(items.length, (i) {
                    final item = items[i];
                    final qty = item['qty'] as double;
                    final rate = item['rate'] as double;
                    final amt = item['amount'] as double;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                                width: 28,
                                child: Text('${i + 1}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black87))),
                            Expanded(
                                flex: 4,
                                child: Text(item['name'] as String,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black87))),
                            SizedBox(
                                width: 36,
                                child: Text(
                                    qty % 1 == 0
                                        ? qty.toInt().toString()
                                        : qty.toStringAsFixed(1),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black87))),
                            SizedBox(
                                width: 56,
                                child: Text(rate.toStringAsFixed(2),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.black87))),
                            SizedBox(
                                width: 64,
                                child: Text(amt.toStringAsFixed(2),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87))),
                          ]),
                    );
                  }),
                  const SizedBox(height: 6),
                  _dash('-'),
                  const SizedBox(height: 10),
                  // Summary
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('No. of Items / பொருட்களின் எண்ணிக்கை:',
                            style: TextStyle(
                                fontSize: 10, color: Colors.black87)),
                        Text('$totalItems',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ]),
                  const SizedBox(height: 4),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Qty / மொத்த அளவு:',
                            style: TextStyle(
                                fontSize: 10, color: Colors.black87)),
                        Text(
                            totalQty % 1 == 0
                                ? totalQty.toInt().toString()
                                : totalQty.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ]),
                  const SizedBox(height: 10),
                  _dash('='),
                  const SizedBox(height: 10),
                  // Grand total
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('GRAND TOTAL',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      color: Colors.black87)),
                              Text('மொத்த தொகை',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54)),
                            ]),
                        Text('₹ ${grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87)),
                      ]),
                  const SizedBox(height: 10),
                  _dash('='),
                  const SizedBox(height: 10),
                  Text('Payment Mode : $paymentMode',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 12),
                  _dash('-'),
                  const SizedBox(height: 16),
                  const Center(
                    child: Column(children: [
                      Text('THANK YOU! VISIT AGAIN!',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      SizedBox(height: 4),
                      Text('நன்றி! மீண்டும் வருக!',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            ), // RepaintBoundary
          ), // inner Center
        ),
      ),
    );
  }

  static Widget _dash(String char) => Text(
        char * 80,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.0,
            color: Colors.black87,
            fontWeight: FontWeight.w600),
      );
}
