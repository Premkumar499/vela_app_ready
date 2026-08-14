import 'package:flutter/material.dart';

import '../utils/theme.dart';

/// POS-style quantity dialog.
/// Uses +/- buttons only – no keyboard entry – as per specification.
class QuantityDialog extends StatefulWidget {
  final double initialQuantity;
  final double step;
  final double minQuantity;

  const QuantityDialog({
    super.key,
    required this.initialQuantity,
    this.step = 1.0,
    this.minQuantity = 0.5,
  });

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late double _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity;
  }

  void _increment() {
    setState(() => _quantity += widget.step);
  }

  void _decrement() {
    if (_quantity - widget.step >= widget.minQuantity) {
      setState(() => _quantity -= widget.step);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 400;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 16 : 40,
        vertical: isNarrow ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.edit_note, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text('Set Quantity', style: AppTheme.headingLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 24),
            // Quantity control row — compact on narrow phones
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 320;
                final btnSize = compact ? 44.0 : 56.0;
                final boxWidth = compact ? 96.0 : 120.0;
                final gap = compact ? 12.0 : 24.0;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Minus button
                    _QuantityButton(
                      icon: Icons.remove,
                      color: AppTheme.error,
                      size: btnSize,
                      onPressed: _decrement,
                      enabled: _quantity - widget.step >= widget.minQuantity,
                    ),
                    SizedBox(width: gap),
                    // Current quantity display
                    Container(
                      width: boxWidth,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.tableHeaderColor,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _quantity % 1 == 0
                            ? _quantity.toInt().toString()
                            : _quantity.toStringAsFixed(2),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                    // Plus button
                    _QuantityButton(
                      icon: Icons.add,
                      color: AppTheme.primary,
                      size: btnSize,
                      onPressed: _increment,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            // Preset quick-select buttons
            Wrap(
              spacing: 8,
              children: [0.5, 1, 2, 5, 10, 25, 50].map((val) {
                final qty = val.toDouble();
                final isSelected = _quantity == qty;
                return ActionChip(
                  label: Text(qty % 1 == 0 ? qty.toInt().toString() : qty.toString()),
                  backgroundColor: isSelected ? AppTheme.primary : null,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  onPressed: () => setState(() => _quantity = qty),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _quantity),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool enabled;
  final double size;

  const _QuantityButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    this.enabled = true,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? color : AppTheme.textSecondary.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.55),
        ),
      ),
    );
  }
}
