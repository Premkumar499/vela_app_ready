import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/billing_provider.dart';
import '../utils/theme.dart';

/// POS-style grand total card displayed at the bottom of the billing screen.
class GrandTotalCard extends StatelessWidget {
  const GrandTotalCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillingProvider>();
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grand total (most prominent element)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GRAND TOTAL', style: AppTheme.grandTotalLabel),
                  SizedBox(height: 2),
                  Text('Incl. GST & Round Off', style: TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                  )),
                ],
              ),
              Text(
                currency.format(provider.grandTotal),
                style: AppTheme.grandTotal,
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 24),
          // Breakdown row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SummaryItem('Subtotal', currency.format(provider.subtotal)),
              _SummaryItem('GST', currency.format(provider.gstTotal)),
              _SummaryItem(
                'Round Off',
                currency.format(provider.roundOff.abs()),
                valuePrefix: provider.roundOff < 0 ? '-' : '+',
              ),
              _SummaryItem('Items', '${provider.itemCount}', isCount: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final String valuePrefix;
  final bool isCount;

  const _SummaryItem(
    this.label,
    this.value, {
    this.valuePrefix = '',
    this.isCount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        const SizedBox(height: 2),
        Text(
          '$valuePrefix$value',
          style: TextStyle(
            fontSize: isCount ? 20 : 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
