import 'package:flutter/material.dart';
import '../utils/pos_theme.dart';

/// Bill summary — no GST, no discount. Shows Grand Total only.
class PosSummarySection extends StatelessWidget {
  final double subtotal;
  final double grandTotal;

  const PosSummarySection({
    super.key,
    required this.subtotal,
    required this.grandTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(PosTheme.padMd),
      padding: const EdgeInsets.symmetric(
        horizontal: PosTheme.padLg,
        vertical: PosTheme.padMd,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(PosTheme.radiusLg),
        boxShadow: PosTheme.elevatedShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GRAND TOTAL',
                  style: PosTheme.caption.copyWith(
                    color: Colors.white60,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: anim, curve: Curves.easeOut)),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Text(
                    '₹${grandTotal.toStringAsFixed(2)}',
                    key: ValueKey(grandTotal),
                    style: PosTheme.amountWhite,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}
