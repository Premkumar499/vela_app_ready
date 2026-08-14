import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/pos_theme.dart';

// ─── Category → Icon mapping ──────────────────────────────────────────────────
IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'grocery':           return Icons.local_grocery_store;
    case 'dairy':             return Icons.local_drink;
    case 'beverages':         return Icons.emoji_food_beverage;
    case 'snacks':            return Icons.cookie_outlined;
    case 'bakery':            return Icons.bakery_dining_outlined;
    case 'oil':               return Icons.opacity;
    case 'rice':              return Icons.grain;
    case 'flour':             return Icons.filter_drama_outlined;
    case 'sugar':             return Icons.lunch_dining_outlined;
    case 'salt':              return Icons.set_meal_outlined;
    case 'pulses':            return Icons.spa_outlined;
    case 'dhall':             return Icons.spa_outlined;
    case 'masala':            return Icons.local_fire_department_outlined;
    case 'spices':            return Icons.local_fire_department_outlined;
    case 'chilly':            return Icons.whatshot_outlined;
    case 'tea & coffee':      return Icons.coffee;
    case 'tea':               return Icons.emoji_food_beverage;
    case 'coffee':            return Icons.coffee;
    case 'dry fruits':        return Icons.eco_outlined;
    case 'millets':           return Icons.grass_outlined;
    case 'briyani':           return Icons.rice_bowl_outlined;
    case 'food':              return Icons.fastfood_outlined;
    case 'appalam':           return Icons.circle_outlined;
    case 'paste':             return Icons.blender_outlined;
    case 'washing items':     return Icons.local_laundry_service_outlined;
    case 'washing soap':      return Icons.soap_outlined;
    case 'cleaning item':     return Icons.cleaning_services_outlined;
    case 'pooja':             return Icons.auto_awesome_outlined;
    case 'poondu':            return Icons.circle_outlined;
    case 'kudal':             return Icons.set_meal_outlined;
    case 'parry':             return Icons.shopping_bag_outlined;
    case 'bala':              return Icons.shopping_bag_outlined;
    case 'vela':              return Icons.store_outlined;
    case 'vela 2':            return Icons.store_outlined;
    default:                  return Icons.inventory_2_outlined;
  }
}

/// Compact POS product card — horizontal layout, fixed height ~88px.
/// Left: small avatar  |  Right: name, category, price + stock row
class PosProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;

  const PosProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  State<PosProductCard> createState() => _PosProductCardState();
}

class _PosProductCardState extends State<PosProductCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_)    => _ctrl.forward();
  void _onTapCancel()   => _ctrl.reverse();
  void _onTapUp(_) async {
    await _ctrl.reverse();
    widget.onTap();
  }

  String get _initial => widget.product.name.isNotEmpty
      ? widget.product.name[0].toUpperCase()
      : '?';

  Color get _color => PosTheme.avatarColor(widget.product.id.hashCode);

  bool get _lowStock => widget.product.availableStock < 10;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown:   _onTapDown,
        onTapUp:     _onTapUp,
        onTapCancel: _onTapCancel,
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: _hovered ? PosTheme.cardHovered : PosTheme.card,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Avatar ───────────────────────────────────────────
                _Avatar(
                  initial:  _initial,
                  color:    _color,
                  icon:     _categoryIcon(widget.product.category),
                  imageUrl: widget.product.imageUrl,
                ),
                const SizedBox(width: 10),

                // ── Info ─────────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Name only (no GST badge)
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: PosTheme.textPrimary,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),

                      // Category
                      Text(
                        widget.product.category,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PosTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Price + Stock row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Price — use product.price directly (no GST)
                          Text(
                            '₹${widget.product.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _color,
                            ),
                          ),
                          Text(
                            ' /${widget.product.unit}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: PosTheme.textHint,
                            ),
                          ),
                          const Spacer(),
                          // Stock
                          _StockPill(
                            stock:  widget.product.availableStock,
                            unit:   widget.product.unit,
                            isLow:  _lowStock,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Avatar ───────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String   initial;
  final Color    color;
  final IconData icon;
  final String?  imageUrl;

  const _Avatar({
    required this.initial,
    required this.color,
    required this.icon,
    this.imageUrl,
  });

  Widget _letterAvatar() => Container(
        width: 56,
        height: 56,
        color: color,
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipOval(
          child: SizedBox(
            width: 56,
            height: 56,
            child: hasImage
                ? Image.network(
                    imageUrl!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _letterAvatar(),
                  )
                : _letterAvatar(),
          ),
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: PosTheme.border, width: 1),
            ),
            child: Icon(icon, size: 10, color: color),
          ),
        ),
      ],
    );
  }
}

class _StockPill extends StatelessWidget {
  final double stock;
  final String unit;
  final bool   isLow;

  const _StockPill({
    required this.stock,
    required this.unit,
    required this.isLow,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isLow ? PosTheme.warning : PosTheme.success;
    final bg = isLow ? PosTheme.warningLight : PosTheme.successLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLow ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 9,
            color: fg,
          ),
          const SizedBox(width: 2),
          Text(
            '${stock.toStringAsFixed(0)} $unit',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
