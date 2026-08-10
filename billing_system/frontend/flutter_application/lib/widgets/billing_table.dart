import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill_item.dart';
import '../utils/theme.dart';
import '../utils/constants.dart';
import 'quantity_dialog.dart';

class BillingTable extends StatelessWidget {
  final List<BillItem> items;
  final Function(int index) onDelete;
  final Function(int index, double quantity) onQuantityChanged;

  const BillingTable({
    super.key,
    required this.items,
    required this.onDelete,
    required this.onQuantityChanged,
  });

  static const _headers = [
    'S.No', 'Item Name', 'Unit', 'Qty',
    'Rate+GST', 'Rate',
    'Amount', 'GST', 'Total', 'Action',
  ];

  // flex widths for each column
  static const _flex = [
    1, 4, 1, 2,
    2, 2,
    2, 2, 2, 1,
  ];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        height: 300,
        decoration: AppTheme.panelDecoration,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 64, color: AppTheme.textSecondary),
              SizedBox(height: 12),
              Text('No items added', style: AppTheme.headingMedium),
              SizedBox(height: 4),
              Text('Search or add items to start billing', style: AppTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final colWidths = { for (var i = 0; i < _flex.length; i++) i: FlexColumnWidth(_flex[i].toDouble()) };

    return Container(
      decoration: AppTheme.panelDecoration,
      width: double.infinity,
      child: Table(
        columnWidths: colWidths,
        border: TableBorder(
          horizontalInside: BorderSide(color: AppTheme.divider, width: 1),
          bottom: BorderSide(color: AppTheme.divider, width: 1),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          // Header row
          TableRow(
            decoration: const BoxDecoration(color: AppTheme.primary),
            children: _headers.map((h) => _headerCell(h)).toList(),
          ),
          // Data rows
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final bg = i.isOdd ? const Color(0xFFF8F9FA) : Colors.white;
            return TableRow(
              decoration: BoxDecoration(color: bg),
              children: [
                _cell(Text('${i + 1}', style: AppTheme.tableCell, textAlign: TextAlign.center)),
                _cell(Text(
                  item.productName,
                  style: AppTheme.tableCell.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
                _cell(Text(item.unit, style: AppTheme.tableCell, textAlign: TextAlign.center)),
                _cell(
                  GestureDetector(
                    onTap: () => _showQuantityDialog(context, i, item.quantity),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.quantity.toStringAsFixed(2),
                            style: AppTheme.tableCell.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit, size: 12, color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
                _cell(Text(currency.format(item.rateWithGst), style: AppTheme.tableCell, textAlign: TextAlign.right)),
                _cell(Text(currency.format(item.rate), style: AppTheme.tableCell, textAlign: TextAlign.right)),
                _cell(Text(currency.format(item.taxableAmount), style: AppTheme.tableCell, textAlign: TextAlign.right)),
                _cell(Text(
                  '${currency.format(item.gstAmount)}\n(${item.gstPercent.toInt()}%)',
                  style: AppTheme.tableCell.copyWith(color: AppTheme.success),
                  textAlign: TextAlign.right,
                )),
                _cell(Text(
                  currency.format(item.total),
                  style: AppTheme.tableCell.copyWith(fontWeight: FontWeight.w700, color: AppTheme.primary),
                  textAlign: TextAlign.right,
                )),
                _cell(
                  IconButton(
                    icon: const Icon(Icons.delete, color: AppTheme.error, size: 18),
                    onPressed: () => onDelete(i),
                    tooltip: 'Remove',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          text,
          style: AppTheme.tableHeaderStyle.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );

  Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: child,
      );

  Future<void> _showQuantityDialog(BuildContext context, int index, double currentQty) async {
    final newQty = await showDialog<double>(
      context: context,
      builder: (_) => QuantityDialog(initialQuantity: currentQty),
    );
    if (newQty != null && newQty > 0) {
      onQuantityChanged(index, newQty);
    }
  }
}
