import 'package:flutter/material.dart';
import '../models/bill_item.dart';
import '../utils/pos_theme.dart';

/// A single row in the bill table.
/// Shows: item name + unit | qty stepper | rate | total | delete button
class PosBillItemRow extends StatelessWidget {
  final int index;
  final BillItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onDelete;

  const PosBillItemRow({
    super.key,
    required this.index,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isAlt = index.isOdd;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isAlt ? PosTheme.surfaceAlt : PosTheme.surface,
        border: const Border(
          bottom: BorderSide(color: PosTheme.border),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width < 600 ? 8.0 : PosTheme.padMd,
          vertical: 10,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;
            if (narrow) return _buildNarrow(context, constraints.maxWidth);
            return _buildWide(context);
          },
        ),
      ),
    );
  }

  // ── Item name column (shared by both layouts) ──────────────────────────
  Widget _buildNameColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.productName,
          style: PosTheme.bodyBold.copyWith(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        _MiniChip(label: item.unit, color: PosTheme.primary),
      ],
    );
  }

  // ── Narrow (phone): name+delete on top, stepper+amounts below ──────────
  Widget _buildNarrow(BuildContext context, double maxWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '${index + 1}',
                style: PosTheme.caption.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: PosTheme.bodyBold.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${item.rate.toStringAsFixed(2)} / ${item.unit}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _DeleteButton(onDelete: onDelete),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _QtyStepper(
              item: item,
              onIncrease: onIncrease,
              onDecrease: onDecrease,
              compact: maxWidth < 220,
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '₹${item.total.toStringAsFixed(2)}',
                  style: PosTheme.bodyBold.copyWith(
                    color: PosTheme.primary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Wide (desktop/tablet): single row ───────────────────────────────────
  Widget _buildWide(BuildContext context) {
    return Row(
      children: [
        // ── Row number ───────────────────────────────────────────────
        SizedBox(
          width: 22,
          child: Text(
            '${index + 1}',
            style: PosTheme.caption.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 8),

        // ── Item name ────────────────────────────────────────────────
        Expanded(flex: 4, child: _buildNameColumn()),

        // ── Qty stepper ──────────────────────────────────────────────
        Expanded(
          flex: 3,
          child: Center(
            child: _QtyStepper(item: item, onIncrease: onIncrease, onDecrease: onDecrease),
          ),
        ),

        // ── Rate ─────────────────────────────────────────────────────
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '₹${item.rate.toStringAsFixed(2)}',
                style: PosTheme.small.copyWith(color: PosTheme.textSecondary),
                maxLines: 1,
              ),
            ),
          ),
        ),

        // ── Total ────────────────────────────────────────────────────
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '₹${item.total.toStringAsFixed(2)}',
                style: PosTheme.bodyBold.copyWith(
                  color: PosTheme.primary,
                  fontSize: 14,
                ),
                maxLines: 1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // ── Delete ───────────────────────────────────────────────────
        _DeleteButton(onDelete: onDelete),
      ],
    );
  }
}

// ─── Quantity stepper ─────────────────────────────────────────────────────────

class _QtyStepper extends StatelessWidget {
  final BillItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final bool compact;

  const _QtyStepper({
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 28 : 36,
      decoration: BoxDecoration(
        color: PosTheme.surface,
        border: Border.all(color: PosTheme.border),
        borderRadius: BorderRadius.circular(PosTheme.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minus
          _StepBtn(
            icon: Icons.remove,
            color: item.quantity <= 1 ? PosTheme.danger : PosTheme.textSecondary,
            onTap: onDecrease,
            roundLeft: true,
            compact: compact,
          ),
          // Quantity display
          Container(
            constraints: BoxConstraints(minWidth: compact ? 22 : 30),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: PosTheme.border),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                _formatQty(item.quantity),
                key: ValueKey(item.quantity),
                style: PosTheme.bodyBold.copyWith(fontSize: compact ? 12 : 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Plus
          _StepBtn(
            icon: Icons.add,
            color: (item.maxStock > 0 && item.quantity >= item.maxStock)
                ? PosTheme.textHint
                : PosTheme.primary,
            onTap: onIncrease,
            roundRight: true,
            compact: compact,
          ),
        ],
      ),
    );
  }

  String _formatQty(double q) =>
      q == q.toInt() ? q.toInt().toString() : q.toStringAsFixed(1);
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool roundLeft;
  final bool roundRight;
  final bool compact;

  const _StepBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.roundLeft = false,
    this.roundRight = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.horizontal(
        left: roundLeft ? const Radius.circular(PosTheme.radiusMd) : Radius.zero,
        right: roundRight ? const Radius.circular(PosTheme.radiusMd) : Radius.zero,
      ),
      child: SizedBox(
        width: compact ? 24 : 30,
        height: compact ? 28 : 36,
        child: Icon(icon, size: compact ? 12 : 16, color: color),
      ),
    );
  }
}

// ─── Delete button ────────────────────────────────────────────────────────────

class _DeleteButton extends StatelessWidget {
  final VoidCallback onDelete;

  const _DeleteButton({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onDelete,
      borderRadius: BorderRadius.circular(PosTheme.radiusSm),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: PosTheme.dangerLight,
          borderRadius: BorderRadius.circular(PosTheme.radiusSm),
        ),
        child: const Icon(Icons.delete_outline_rounded, size: 17, color: PosTheme.danger),
      ),
    );
  }
}

// ─── Mini chip ────────────────────────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─── Empty cart placeholder ────────────────────────────────────────────────────

class PosEmptyCartPlaceholder extends StatelessWidget {
  const PosEmptyCartPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isNarrow ? 48 : 80,
            height: isNarrow ? 48 : 80,
            decoration: const BoxDecoration(
              color: PosTheme.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: isNarrow ? 24 : 38,
              color: PosTheme.primary,
            ),
          ),
          SizedBox(height: isNarrow ? 8 : 16),
          Text(
            'No items added',
            style: isNarrow ? PosTheme.bodyBold.copyWith(fontSize: 13) : PosTheme.bodyBold,
          ),
          if (!isNarrow) ...[
            const SizedBox(height: 6),
            const Text(
              'Tap a product to add it\nto the current bill',
              style: PosTheme.small,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
