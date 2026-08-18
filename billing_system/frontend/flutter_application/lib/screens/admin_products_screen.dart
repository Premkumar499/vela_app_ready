import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

/// Admin product management – full CRUD against the Supabase backend.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  List<Product> _allProducts = [];
  List<Product> _filtered = [];
  List<String> _categories = [];
  String _selectedCategory = 'All';
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedProductIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSelection(String productId) {
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
        if (_selectedProductIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedProductIds.add(productId);
      }
    });
  }

  void _onTileLongPress(String productId) {
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
        _selectedProductIds.add(productId);
      });
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedProductIds.clear();
      _isSelectionMode = false;
    });
  }

  bool get _isAllSelected =>
      _filtered.isNotEmpty && _selectedProductIds.length == _filtered.length;

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedProductIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedProductIds.addAll(_filtered.map((p) => p.id));
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelectedProducts() async {
    final count = _selectedProductIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Products'),
        content: Text('Delete $count selected product(s)? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    final productIdsToDelete = _selectedProductIds.toList();
    final result = await ApiService.bulkDeleteProducts(productIdsToDelete);
    if (!mounted) return;

    setState(() {
      _selectedProductIds.clear();
      _isSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          result.success ? '$count products deleted.' : result.error ?? 'Failed to delete products.'),
      backgroundColor: result.success ? AppTheme.success : AppTheme.error,
    ));

    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getProducts();

    if (!mounted) return;

    if (result.success) {
      final products = result.data!;
      final cats = <String>{'All'};
      for (final p in products) {
        if (p.category != 'Function Bill Products') cats.add(p.category);
      }
      setState(() {
        _allProducts = products;
        _categories = cats.toList();
        _applyFilter();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _allProducts.where((p) {
        if (p.category == 'Function Bill Products') return false;
        final matchesSearch = query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query);
        final matchesCategory =
            _selectedCategory == 'All' || p.category == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _selectCategory(String cat) {
    setState(() => _selectedCategory = cat);
    _applyFilter();
  }

  Future<void> _openForm([Product? product]) async {
    final saved = await showDialog<Product?>(
      context: context,
      builder: (_) => _ProductFormDialog(product: product),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(product == null
            ? 'Product "${saved.name}" created.'
            : 'Product "${saved.name}" updated.'),
        backgroundColor: AppTheme.success,
      ));
      _loadProducts();
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text(
            'Delete "${product.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final result = await ApiService.deleteProduct(product.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? 'Product "${product.name}" deleted.'
          : result.error ?? ''),
      backgroundColor: result.success ? AppTheme.success : AppTheme.error,
    ));

    if (result.success) _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: _isSelectionMode
            ? Text('${_selectedProductIds.length} selected')
            : Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Manage Products',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: Icon(_isAllSelected ? Icons.deselect : Icons.select_all),
                  tooltip: _isAllSelected ? 'Deselect All' : 'Select All',
                  onPressed: _toggleSelectAll,
                ),
                if (_selectedProductIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    tooltip: 'Delete Selected',
                    onPressed: _deleteSelectedProducts,
                  ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.playlist_add_check),
                  tooltip: 'Select Products',
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = true;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadProducts,
                  tooltip: 'Refresh',
                ),
              ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search products…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon:
                                const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilter();
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
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final cat in _categories) _buildCategoryChip(cat),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _filtered.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 56, color: AppTheme.textSecondary),
                          SizedBox(height: 12),
                          Text('No products found',
                              style: AppTheme.headingMedium),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadProducts,
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.only(bottom: 84, top: 4),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final product = _filtered[i];
                          final isSelected = _selectedProductIds.contains(product.id);
                          return _ProductTile(
                            product: product,
                            isSelected: isSelected,
                            isSelectionMode: _isSelectionMode,
                            onTap: () {
                              if (_isSelectionMode) {
                                _toggleSelection(product.id);
                              } else {
                                _openForm(product);
                              }
                            },
                            onLongPress: () => _onTileLongPress(product.id),
                            onEdit: () => _openForm(product),
                            onDelete: () => _deleteProduct(product),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildCategoryChip(String cat) {
    final selected = _selectedCategory == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        onTap: () => _selectCategory(cat),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.3),
            ),
          ),
          child: Center(
            child: Text(
              cat,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? AppTheme.primary : Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 56, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product tile
// ─────────────────────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final isLowStock = product.stock < 10;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      color: isSelected ? AppTheme.primary.withValues(alpha: 0.05) : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (isSelectionMode) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => onTap(),
                  activeColor: AppTheme.primary,
                ),
                const SizedBox(width: 4),
              ],
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.headingSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(product.category, AppTheme.info),
                        _Chip(product.unit, AppTheme.textSecondary),
                        _Chip(
                          'Stock ${product.stock.toStringAsFixed(0)}',
                          isLowStock ? AppTheme.error : AppTheme.success,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(currency.format(product.price),
                      style: AppTheme.headingMedium
                          .copyWith(color: AppTheme.primary)),
                  if (!isSelectionMode) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: AppTheme.primary, size: 20),
                          onPressed: onEdit,
                          tooltip: 'Edit',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppTheme.error, size: 20),
                          onPressed: onDelete,
                          tooltip: 'Delete',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit form dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ProductFormDialog extends StatefulWidget {
  final Product? product;

  const _ProductFormDialog({this.product});

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _skuCtrl;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _categoryCtrl = TextEditingController(text: p?.category ?? '');
    _unitCtrl = TextEditingController(text: p?.unit ?? 'PCS');
    _priceCtrl = TextEditingController(
        text: p != null ? p.price.toStringAsFixed(2) : '');
    _stockCtrl = TextEditingController(
        text: p != null ? p.stock.toStringAsFixed(2) : '');
    _skuCtrl = TextEditingController(text: p?.sku ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _skuCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    final stock = double.tryParse(_stockCtrl.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Product name is required');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price (0 or more)');
      return;
    }
    if (stock == null || stock < 0) {
      setState(() => _error = 'Enter a valid stock quantity (0 or more)');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final ApiResult<Product> result;
    if (_isEdit) {
      final edited = Product(
        id: widget.product!.id,
        name: name,
        unit: _unitCtrl.text.trim().isEmpty ? 'PCS' : _unitCtrl.text.trim(),
        price: price,
        mrp: price,
        stock: stock,
        category: _categoryCtrl.text.trim().isEmpty
            ? 'General'
            : _categoryCtrl.text.trim(),
        description: _skuCtrl.text.trim(),
      );
      result = await ApiService.updateProduct(edited);
    } else {
      result = await ApiService.createProduct(
        name: name,
        category: _categoryCtrl.text.trim().isEmpty
            ? 'General'
            : _categoryCtrl.text.trim(),
        unit: _unitCtrl.text.trim().isEmpty ? 'PCS' : _unitCtrl.text.trim(),
        price: price,
        stock: stock,
        sku: _skuCtrl.text.trim(),
      );
    }

    if (!mounted) return;

    if (result.success) {
      Navigator.pop(context, result.data);
    } else {
      setState(() {
        _saving = false;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 500 ? screenWidth - 48 : 450.0;
    final twoCols = dialogWidth >= 340;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Product' : 'Add Product'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Product Name *',
                  prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              if (twoCols)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _categoryCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _unitCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          prefixIcon: Icon(Icons.straighten, size: 20),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                TextField(
                  controller: _categoryCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _unitCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    prefixIcon: Icon(Icons.straighten, size: 20),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (twoCols)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Price (₹) *',
                          prefixIcon: Icon(Icons.currency_rupee, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _stockCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Stock *',
                          prefixIcon: Icon(Icons.warehouse_outlined, size: 20),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                TextField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price (₹) *',
                    prefixIcon: Icon(Icons.currency_rupee, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stockCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Stock *',
                    prefixIcon: Icon(Icons.warehouse_outlined, size: 20),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _skuCtrl,
                decoration: const InputDecoration(
                  labelText: 'SKU / Barcode (optional)',
                  prefixIcon: Icon(Icons.qr_code_2, size: 20),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'Save Changes' : 'Add Product'),
        ),
      ],
    );
  }
}
