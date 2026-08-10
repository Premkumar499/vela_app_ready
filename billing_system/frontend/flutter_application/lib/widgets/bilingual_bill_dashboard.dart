import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/invoice_export_service.dart';

class BilingualBillDashboard extends StatefulWidget {
  final Map<String, dynamic> receiptData;
  final VoidCallback onClose;

  const BilingualBillDashboard({
    super.key,
    required this.receiptData,
    required this.onClose,
  });

  @override
  State<BilingualBillDashboard> createState() => _BilingualBillDashboardState();
}

class _BilingualBillDashboardState extends State<BilingualBillDashboard> {
  String _billNo = '';
  String _date = '';
  String _time = '';
  String _paymentMode = 'CASH';
  List<Map<String, dynamic>> _items = [];
  final String _receiptLanguage = 'bilingual';
  bool _isTranslating = false;
  bool _isSaving = false;
  bool _autoSaved = false;
  final GlobalKey _receiptKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadFromReceiptData(widget.receiptData);
    
    // Schedule auto-save after widget is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      print('[BilingualBillDashboard] PostFrameCallback triggered');
      
      await _translateAll();
      print('[BilingualBillDashboard] Translation complete, bill_no: $_billNo');
      
      // Small delay to ensure the widget is fully painted after translation
      await Future.delayed(const Duration(milliseconds: 400));
      print('[BilingualBillDashboard] Delay complete, calling _autoSaveBoth');
      
      await _autoSaveBoth();  // MUST await to catch errors!
      print('[BilingualBillDashboard] _autoSaveBoth completed');
    });
  }

  void _loadFromReceiptData(Map<String, dynamic> data) {
    final invoice  = (data['invoice']  as Map<String, dynamic>?) ?? {};
    final payment  = (data['payment']  as Map<String, dynamic>?) ?? {};
    final rawItems = (data['items']    as List<dynamic>?)         ?? [];

    _billNo      = invoice['bill_no']?.toString() ?? '';
    _date        = invoice['date']?.toString()    ?? '';
    _time        = invoice['time']?.toString()    ?? '';
    _paymentMode = payment['method']?.toString().toUpperCase() ?? 'CASH';

    _items = rawItems.map((e) {
      final m = e as Map<String, dynamic>;
      double parseNum(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString()) ?? 0.0;
      }
      return {
        'description':      m['product_name']?.toString() ?? '',
        'descriptionTamil': '',
        'qty':      parseNum(m['qty']),
        'rate':     parseNum(m['rate']),
        'weight':   0.0,
        'amount':   m['amount'],
        'unit':     m['unit']?.toString() ?? '',
        'discount': m['discount'] ?? 0,
      };
    }).toList();
  }

  Future<void> _translateAll() async {
    final toTranslate = <int, String>{};
    for (var i = 0; i < _items.length; i++) {
      final ta = _items[i]['descriptionTamil'] as String? ?? '';
      if (ta.isEmpty) toTranslate[i] = _items[i]['description'] as String? ?? '';
    }
    if (toTranslate.isEmpty) return;
    setState(() => _isTranslating = true);
    final indices = toTranslate.keys.toList();
    final texts   = toTranslate.values.toList();
    try {
      final translated = await ApiService.translateToTamil(texts);
      if (!mounted) return;
      setState(() {
        for (var j = 0; j < indices.length; j++) {
          _items[indices[j]]['descriptionTamil'] = translated[j];
        }
        _isTranslating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isTranslating = false);
    }
  }

  /// Automatically save: customer receipt → erp_billing_system,
  /// company invoice → erp_billing_system_company (server-side PDF from DB).
  Future<void> _autoSaveBoth() async {
    if (_autoSaved || _billNo.isEmpty || !mounted) {
      print('[BilingualBillDashboard] _autoSaveBoth skipped: autoSaved=$_autoSaved, billNo=$_billNo, mounted=$mounted');
      return;
    }
    _autoSaved = true;

    print('[BilingualBillDashboard] _autoSaveBoth START for bill: $_billNo');

    try {
      // 1. Customer bill: capture receipt widget → erp_billing_system bucket
      print('[BilingualBillDashboard] Step 1: Capturing customer receipt...');
      final customerResult = await InvoiceExportService.saveInvoiceAsImage(
        widgetKey: _receiptKey,
        invoiceNumber: _billNo,
        isCompanyInvoice: false,
      );
      print('[BilingualBillDashboard] Customer bill result: ${customerResult['success']}, message: ${customerResult['message']}');

      if (!mounted) {
        print('[BilingualBillDashboard] Widget unmounted after customer bill, stopping');
        return;
      }

      // Small delay to ensure DB transaction is fully committed
      print('[BilingualBillDashboard] Waiting 500ms for DB commit...');
      await Future.delayed(const Duration(milliseconds: 500));

      // 2. Company invoice: server-side PDF from DB → erp_billing_system_company bucket
      print('[BilingualBillDashboard] Step 2: Calling generateCompanyInvoice for: $_billNo');
      final companyResult = await InvoiceExportService.generateCompanyInvoice(_billNo);
      print('[BilingualBillDashboard] Company invoice result: ${companyResult['success']}, message: ${companyResult['message']}');

      if (companyResult['success'] != true) {
        print('[BilingualBillDashboard] ❌ ERROR: Company invoice failed: ${companyResult['message']}');
      } else {
        print('[BilingualBillDashboard] ✅ SUCCESS: Company invoice uploaded to bucket');
      }
    } catch (e, stackTrace) {
      print('[BilingualBillDashboard] ❌ EXCEPTION in _autoSaveBoth: $e');
      print('[BilingualBillDashboard] Stack trace: $stackTrace');
    }
  }

  Future<void> _saveReceipt() async {
    setState(() => _isSaving = true);
    final result = await InvoiceExportService.saveInvoiceAsImage(
      widgetKey: _receiptKey,
      invoiceNumber: _billNo,
      isCompanyInvoice: false,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result['success'] == true
          ? 'Saved: ${result['bucket'] ?? ''}/${result['fileName'] ?? ''}'
          : result['message']?.toString() ?? 'Failed to save'),
      backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      duration: const Duration(seconds: 4),
    ));
  }

  double get _totalQty    => _items.fold(0.0, (s, i) => s + (i['qty']    as double));
  double get _totalWeight => _items.fold(0.0, (s, i) => s + (i['weight'] as double));
  double get _totalAmount => _items.fold(0.0, (s, i) => s + ((i['qty'] as double) * (i['rate'] as double)));
  int    get _totalItems  => _items.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: widget.onClose,
        ),
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Colors.blueAccent, size: 26),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Receipt Preview',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                Text('Bill · $_billNo',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_alt, color: Colors.white),
              tooltip: 'Save as Image',
              onPressed: _saveReceipt,
            ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.blueAccent),
            tooltip: 'Print Receipt',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Receipt sent to thermal printer...'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: widget.onClose,
            icon: const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
            label: const Text('Done', style: TextStyle(color: Colors.greenAccent)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
            color: const Color(0xFF0F172A),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isTranslating)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                            ),
                            SizedBox(width: 8),
                            Text('Translating items to Tamil...',
                                style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    _buildThermalReceipt(),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildThermalReceipt() {
    return Center(
      child: RepaintBoundary(
        key: _receiptKey,
        child: Container(
          width: 380,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _SawToothPainter(),
            child: Container(
              color: const Color(0xFFF9F6EE),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _receiptHeader(),
                  const SizedBox(height: 12),
                  _divider('-'),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text('INVOICE / CASH BILL',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.black87)),
                  ),
                  const SizedBox(height: 8),
                  _divider('-'),
                  const SizedBox(height: 12),
                  _billMeta(),
                  const SizedBox(height: 12),
                  _divider('-'),
                  const SizedBox(height: 8),
                  _tableHeader(),
                  const SizedBox(height: 8),
                  _divider('-'),
                  const SizedBox(height: 8),
                  _itemsList(),
                  const SizedBox(height: 8),
                  _divider('-'),
                  const SizedBox(height: 12),
                  _summaryDetails(),
                  const SizedBox(height: 12),
                  _divider('='),
                  const SizedBox(height: 12),
                  _totalRow(),
                  const SizedBox(height: 12),
                  _divider('='),
                  const SizedBox(height: 12),
                  Text('Payment Mode : $_paymentMode',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  _divider('-'),
                  const SizedBox(height: 20),
                  const Center(
                    child: Column(
                      children: [
                        Text('THANK YOU! VISIT AGAIN!',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                        SizedBox(height: 4),
                        Text('நன்றி! மீண்டும் வருக!',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Image.asset('assets/images/logo.jpg', width: 80, height: 80, fit: BoxFit.contain),
        ),
        const SizedBox(height: 10),
        const Text('VELA AGENCY',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.black87)),
        const SizedBox(height: 10),
        const Text('மளிகை மொத்த மற்றும் சில்லறை\nவியாபாரம்...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.5)),
        const SizedBox(height: 8),
        const Text('பர்கூர் ரோடு, வெள்ளை பிள்ளையார்\nகோவில், அந்தியூர்.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.5)),
      ],
    );
  }

  Widget _billMeta() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bill No : $_billNo',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 6),
              Text('Time    : $_time',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
        ),
        Text('Date : $_date',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _tableHeader() {
    return const Row(
      children: [
        SizedBox(width: 28, child: Text('SNo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
        Expanded(flex: 4, child: Text('Description / விவரம்', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
        SizedBox(width: 36, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
        SizedBox(width: 56, child: Text('Rate', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
        SizedBox(width: 64, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
      ],
    );
  }

  Widget _itemsList() {
    return Column(
      children: List.generate(_items.length, (i) {
        final item   = _items[i];
        final en     = item['description'] as String? ?? '';
        final ta     = item['descriptionTamil'] as String? ?? '';
        final qty    = item['qty']  as double;
        final rate   = item['rate'] as double;
        final amt    = item['amount'] ?? (qty * rate);
        final isLast = i == _items.length - 1;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.black87))),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_receiptLanguage == 'english' || _receiptLanguage == 'bilingual')
                          Text(en, style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500)),
                        if (_receiptLanguage == 'bilingual' && ta.isNotEmpty) const SizedBox(height: 2),
                        if (_receiptLanguage == 'tamil' || (_receiptLanguage == 'bilingual' && ta.isNotEmpty))
                          Text(
                            _receiptLanguage == 'tamil' ? (ta.isNotEmpty ? ta : en) : ta,
                            style: TextStyle(
                              fontSize: 10,
                              color: _receiptLanguage == 'tamil' ? Colors.black87 : Colors.black54,
                              fontWeight: _receiptLanguage == 'tamil' ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: 36, child: Text(qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(1), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.black87))),
                  SizedBox(width: 56, child: Text(rate.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.black87))),
                  SizedBox(width: 64, child: Text(amt is double ? amt.toStringAsFixed(2) : '$amt', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
                ],
              ),
            ),
            if (!isLast) _divider('·', spacing: 2.0, color: Colors.black26),
          ],
        );
      }),
    );
  }

  Widget _summaryDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('No. of Items / பொருட்களின் எண்ணிக்கை:', style: TextStyle(fontSize: 10, color: Colors.black87)),
          Text('$_totalItems', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total Qty / மொத்த அளவு:', style: TextStyle(fontSize: 10, color: Colors.black87)),
          Text(_totalQty % 1 == 0 ? _totalQty.toInt().toString() : _totalQty.toStringAsFixed(1),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
        ]),
        if (_totalWeight > 0) ...[
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total Weight / மொத்த எடை:', style: TextStyle(fontSize: 10, color: Colors.black87)),
            Text('${_totalWeight.toStringAsFixed(3)} kg', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
          ]),
        ],
      ],
    );
  }

  Widget _totalRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GRAND TOTAL', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.black87)),
            Text('மொத்த தொகை', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
          ],
        ),
        Text('₹ ${_totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _divider(String char, {double spacing = 1.0, Color color = Colors.black87}) => Text(
        char * 80,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: 11, letterSpacing: spacing, color: color, fontWeight: FontWeight.w600),
      );
}

class _SawToothPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tw = 8.0;
    const th = 5.0;
    final paint = Paint()
      ..color = const Color(0xFFF9F6EE)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, th);
    for (double x = 0; x < size.width; x += tw) {
      path.lineTo(x + tw / 2, 0);
      path.lineTo(x + tw, th);
    }
    path.lineTo(size.width, size.height - th);
    for (double x = size.width; x > 0; x -= tw) {
      path.lineTo(x - tw / 2, size.height);
      path.lineTo(x - tw, size.height - th);
    }
    path.lineTo(0, th);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
