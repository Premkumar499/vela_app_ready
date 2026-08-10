// ============================================================
// MAIN INVOICE PREVIEW WIDGET
// ============================================================

import 'package:flutter/material.dart';
import '../models/invoice_model.dart';
import '../utils/currency_formatter.dart';
import '../utils/number_to_words.dart';

class InvoicePreview extends StatelessWidget {
  final Invoice invoice;

  const InvoicePreview({super.key, required this.invoice});

  // Color Scheme
  static const _navy = Color(0xFF1B2A4A);
  static const _lightBlueBg = Color(0xFFF3F6FC);
  static const _headerBg = Color(0xFFE7ECF6);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _topHeader(),
          const SizedBox(height: 18),
          Divider(color: Colors.grey.shade300, thickness: 1),
          const SizedBox(height: 14),
          _billTo(),
          const SizedBox(height: 18),
          _itemsTable(),
          const SizedBox(height: 18),
          _paymentAndTotal(),
          const SizedBox(height: 18),
          _bankAndSignature(),
          const SizedBox(height: 20),
          _footer(),
        ],
      ),
    );
  }

  // Top header with company info and invoice metadata
  Widget _topHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Company logo image - full size
                  Image.asset(
                    'assets/images/company_logo.jpg',
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to icon if image fails to load
                      return Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _navy,
                        ),
                        child: const Icon(Icons.storefront,
                            color: Colors.white, size: 20),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Invoice.companyName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  Invoice.companyAddress,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800),
                ),
              ),
              const SizedBox(height: 6),
              _kv('GSTIN', Invoice.companyGstin),
              _kv('FSSAI', Invoice.companyFssai),
              _kv('PAN', Invoice.companyPan),
              _kv('Phone', Invoice.companyPhone),
              _kv('Email', Invoice.companyEmail),
            ],
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _lightBlueBg,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metaRow('Invoice No:', invoice.invoiceNo),
              const SizedBox(height: 4),
              _metaRow('Date:', invoice.invoiceDate),
              if (invoice.invoiceTime.isNotEmpty) ...[
                const SizedBox(height: 4),
                _metaRow('Time:', invoice.invoiceTime),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaRow(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: _navy)),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade900),
          children: [
            TextSpan(
                text: '$label:  ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  // Bill To section
  Widget _billTo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('BILL TO',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _navy,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(invoice.customerName,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
        const SizedBox(height: 4),
        Text(invoice.customerAddress,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800)),
        if (invoice.customerGstin.isNotEmpty && invoice.customerGstin != 'N/A') ...[
          const SizedBox(height: 4),
          _kv('GSTIN', invoice.customerGstin),
        ],
        if (invoice.customerPan.isNotEmpty && invoice.customerPan != 'N/A') ...[
          const SizedBox(height: 4),
          _kv('PAN', invoice.customerPan),
        ],
      ],
    );
  }

  // Items table
  Widget _itemsTable() {
    final headerStyle = const TextStyle(
        fontSize: 10.5, fontWeight: FontWeight.bold, color: _navy);
    final cellStyle = TextStyle(fontSize: 11, color: Colors.grey.shade900);

    // Check if any item has HSN code
    final hasHsn = invoice.items.any((item) => item.hsn.isNotEmpty);

    List<Widget> headerRow = [
      _cell('S.NO', headerStyle, flex: 1),
      _cell('DESCRIPTION', headerStyle, flex: 5, align: TextAlign.left),
      if (hasHsn) _cell('HSN', headerStyle, flex: 2),
      _cell('UNIT', headerStyle, flex: 2),
      _cell('QTY', headerStyle, flex: 2),
      _cell('RATE', headerStyle, flex: 2, align: TextAlign.right),
      _cell('AMOUNT', headerStyle, flex: 3, align: TextAlign.right),
    ];

    return Column(
      children: [
        Container(
          color: _headerBg,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(children: headerRow),
        ),
        ...invoice.items.asMap().entries.map((e) {
          final idx = e.key;
          final item = e.value;
          final isAlt = idx % 2 == 1;
          return Container(
            color: isAlt ? _lightBlueBg : Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cell('${idx + 1}', cellStyle, flex: 1),
                _cell(item.description, cellStyle,
                    flex: 5, align: TextAlign.left),
                if (hasHsn) _cell(item.hsn, cellStyle, flex: 2),
                _cell(item.unit, cellStyle, flex: 2),
                _cell(_fmtNum(item.qty), cellStyle, flex: 2),
                _cell(_fmtNum(item.rate), cellStyle,
                    flex: 2, align: TextAlign.right),
                _cell(_fmtNum(item.amount),
                    cellStyle.copyWith(fontWeight: FontWeight.w700),
                    flex: 3, align: TextAlign.right),
              ],
            ),
          );
        }),
        Divider(color: Colors.grey.shade300, height: 1),
      ],
    );
  }

  String _fmtNum(double v) => v.toStringAsFixed(2);

  Widget _cell(String text, TextStyle style,
      {int flex = 1, TextAlign align = TextAlign.center}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: style, textAlign: align),
    );
  }

  // Payment details and total
  Widget _paymentAndTotal() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PAYMENT DETAILS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              _kv('Mode', invoice.paymentMode),
              _kv('Txn ID', invoice.txnId),
              _kv('UPI ID', invoice.upiId),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('TOTAL AMOUNT',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      const SizedBox(width: 18),
                      Text(formatCurrency(invoice.totalAmount),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Words: ${NumberToWords.amountInWords(invoice.totalAmount)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Bank details and signature section
  Widget _bankAndSignature() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('BANK DETAILS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              _kv('Bank', Invoice.bankName),
              _kv('A/C', Invoice.accountNo),
              _kv('IFSC', Invoice.ifsc),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FOR VELA AGENCY',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(height: 28),
                Divider(color: Colors.grey.shade400, height: 1),
                const SizedBox(height: 4),
                const Text('Authorized Signatory',
                    style: TextStyle(fontSize: 10.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Footer
  Widget _footer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _lightBlueBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          const Text('Thank you for your business.',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12, color: _navy)),
          const SizedBox(height: 4),
          Text(
            'We declare that this invoice shows the actual price of the goods described and that all particulars are true and correct',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
