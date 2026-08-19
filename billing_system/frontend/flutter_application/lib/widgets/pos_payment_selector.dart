import 'package:flutter/material.dart';
import '../utils/pos_theme.dart';

/// Horizontal payment method selector with animated selection indicator.
class PosPaymentSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  static const _methods = [
    _PayMethod('Cash',   Icons.payments_outlined),
    _PayMethod('UPI',    Icons.qr_code_rounded),
    _PayMethod('Card',   Icons.credit_card_rounded),
    _PayMethod('Credit', Icons.account_balance_wallet_outlined),
  ];

  const PosPaymentSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: PosTheme.padMd,
            bottom: PosTheme.padSm,
          ),
          child: Text(
            'PAYMENT METHOD',
            style: PosTheme.caption.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: PosTheme.textSecondary,
            ),
          ),
        ),
        SizedBox(
          height: 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PosTheme.padMd),
            itemCount: _methods.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final m = _methods[i];
              final isSelected = selected == m.label;
              return _PayMethodChip(
                method: m,
                isSelected: isSelected,
                onTap: () => onChanged(m.label),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PayMethodChip extends StatelessWidget {
  final _PayMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  const _PayMethodChip({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSelected ? PosTheme.primary : PosTheme.surface,
        borderRadius: BorderRadius.circular(PosTheme.radiusMd),
        border: Border.all(
          color: isSelected ? PosTheme.primary : PosTheme.border,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected ? PosTheme.elevatedShadow : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PosTheme.radiusMd),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isNarrow) ...[
                // Radio indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : PosTheme.border,
                      width: 2,
                    ),
                    color: isSelected ? Colors.white : Colors.transparent,
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: PosTheme.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                method.icon,
                size: 16,
                color: isSelected ? Colors.white : PosTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                method.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : PosTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayMethod {
  final String label;
  final IconData icon;
  const _PayMethod(this.label, this.icon);
}
