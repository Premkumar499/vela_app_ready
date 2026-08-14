import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../utils/theme.dart';

/// Warehouse Manager screen – read-only, three sections:
///   1. Product list (with live stock)
///   2. Barcode list
///   3. Stock in/out movement
/// All data comes from the backend (Supabase) via ApiService.
class WarehouseManagerScreen extends StatefulWidget {
  const WarehouseManagerScreen({super.key});

  @override
  State<WarehouseManagerScreen> createState() => _WarehouseManagerScreenState();
}

class _WarehouseManagerScreenState extends State<WarehouseManagerScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Warehouse Manager',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: () async {
                await SessionService.clearSession();
                if (!context.mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login', (route) => false);
              },
            ),
          ],
          bottom: TabBar(
            onTap: (i) => setState(() => _tabIndex = i),
            tabs: const [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Products'),
              Tab(icon: Icon(Icons.qr_code_2), text: 'Barcodes'),
              Tab(icon: Icon(Icons.swap_vert), text: 'Stock In/Out'),
            ],
          ),
        ),
        body: IndexedStack(
          index: _tabIndex,
          children: const [
            _ProductListTab(),
            _BarcodeListTab(),
            _MovementListTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search…',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white70),
                  onPressed: () {
                    controller.clear();
                    onChanged();
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
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String message;

  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(message, style: AppTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 – Product list
// ---------------------------------------------------------------------------

class _ProductListTab extends StatefulWidget {
  const _ProductListTab();

  @override
  State<_ProductListTab> createState() => _ProductListTabState();
}

class _ProductListTabState extends State<_ProductListTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.getWarehouseProducts(
      search: _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _loading = false;
        _rows = result.data ?? [];
      });
    } else {
      setState(() {
        _loading = false;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(controller: _searchCtrl, onChanged: _load),
        const SizedBox(height: 4),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const _EmptyView(message: 'No products found');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = _rows[i];
          final stock = (p['current_stock'] as num).toDouble();
          final reserved = (p['reserved_stock'] as num).toDouble();
          final available = (p['available_stock'] as num).toDouble();
          final lowStock =
              available <= (p['minimum_stock'] as num? ?? 0).toDouble();
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: lowStock
                  ? AppTheme.error.withValues(alpha: 0.15)
                  : AppTheme.success.withValues(alpha: 0.15),
              child: Text(
                (p['name'] as String? ?? '').isEmpty
                    ? '?'
                    : (p['name'] as String).substring(0, 1),
                style: TextStyle(
                    color: lowStock ? AppTheme.error : AppTheme.success,
                    fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              p['name'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                p['category'] as String? ?? '',
                p['unit'] as String? ?? '',
                if ((p['brand'] as String? ?? '').isNotEmpty)
                  p['brand'] as String,
                '₹${p['price']}',
              ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall,
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Avail: $available',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.success),
                ),
                Text(
                  'Stock: $stock (res. $reserved)',
                  style: AppTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 – Barcode list
// ---------------------------------------------------------------------------

class _BarcodeListTab extends StatefulWidget {
  const _BarcodeListTab();

  @override
  State<_BarcodeListTab> createState() => _BarcodeListTabState();
}

class _BarcodeListTabState extends State<_BarcodeListTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.getWarehouseBarcodes(
      search: _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _loading = false;
        _rows = result.data ?? [];
      });
    } else {
      setState(() {
        _loading = false;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(controller: _searchCtrl, onChanged: _load),
        const SizedBox(height: 4),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const _EmptyView(message: 'No barcodes found');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final b = _rows[i];
          final barcode = b['barcode'] as String? ?? '';
          final sku = b['sku'] as String? ?? '';
          final itemCode = b['item_code'] as String? ?? '';
          return ListTile(
            dense: true,
            leading: const Icon(Icons.qr_code_2, color: AppTheme.primary),
            title: Text(
              b['name'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              barcode.isNotEmpty ? barcode : (sku.isNotEmpty ? sku : itemCode),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'monospace', color: AppTheme.textSecondary),
            ),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (barcode.isNotEmpty)
                  _CodeChip(label: 'BAR', value: barcode),
                if (sku.isNotEmpty) _CodeChip(label: 'SKU', value: sku),
                if (itemCode.isNotEmpty)
                  _CodeChip(label: 'ITM', value: itemCode),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String label;
  final String value;

  const _CodeChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.tableHeaderColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 – Stock in/out movement
// ---------------------------------------------------------------------------

class _MovementListTab extends StatefulWidget {
  const _MovementListTab();

  @override
  State<_MovementListTab> createState() => _MovementListTabState();
}

class _MovementListTabState extends State<_MovementListTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.getStockMovements(
      search: _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _loading = false;
        _rows = result.data ?? [];
      });
    } else {
      setState(() {
        _loading = false;
        _error = result.error;
      });
    }
  }

  (Color, IconData, String) _movementStyle(String movement) {
    switch (movement) {
      case 'IN':
        return (AppTheme.success, Icons.south_west, 'Stock In');
      case 'OUT':
        return (AppTheme.error, Icons.north_east, 'Stock Out');
      case 'HOLD':
        return (AppTheme.warning, Icons.pause_circle_outline, 'On Hold');
      default:
        return (AppTheme.textSecondary, Icons.help_outline, movement);
    }
  }

  String _fmtTime(Object? value) {
    if (value == null || value.toString().isEmpty) return '—';
    final s = value.toString();
    // ISO timestamps from Supabase: 2026-08-14T05:43:55.047491+00:00
    if (s.length >= 16) return s.substring(0, 16).replaceFirst('T', ' ');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(controller: _searchCtrl, onChanged: _load),
        const SizedBox(height: 4),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const _EmptyView(message: 'No stock movements yet');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final m = _rows[i];
          final (color, icon, label) =
              _movementStyle(m['movement'] as String? ?? '');
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(
              m['name'] as String? ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_fmtTime(m['reserved_at'])} · Bill ${m['bill_id']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall,
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${m['quantity']} ${m['unit']}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: color),
                ),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          );
        },
      ),
    );
  }
}
