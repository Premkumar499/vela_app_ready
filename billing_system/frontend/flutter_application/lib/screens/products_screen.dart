import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../widgets/product_card.dart';

/// Product listing screen.
/// Used both as a standalone browse view and as a picker (when [isPicker] is true).
/// Falls back to the local dummy dataset when the backend is unreachable.
class ProductsScreen extends StatefulWidget {
  final bool isPicker;

  const ProductsScreen({super.key, this.isPicker = false});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _allProducts = [];
  List<Product> _filtered = [];
  String _selectedCategory = 'All';
  bool _isLoading = true;
  bool _isOffline = false;
  final TextEditingController _searchCtrl = TextEditingController();

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

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    final result = await ApiService.getProducts();

    if (!mounted) return;

    if (result.success) {
      final products = result.data!;
      setState(() {
        _allProducts = products;
        _isOffline = result.isOffline;
        _applyFilter();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
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

  void _onProductTap(Product product) {
    if (widget.isPicker) {
      Navigator.pop(context, product);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} – ₹${product.priceWithGst}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPicker ? 'Select Product' : 'Products'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search products…',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
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
        ),
      ),
      body: Column(
        children: [
          // Offline banner
          if (_isOffline)
            Container(
              width: double.infinity,
              color: AppTheme.warning.withValues(alpha: 0.12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off,
                      size: 16, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Backend unreachable — showing local demo data',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.warning,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadProducts,
                    child: const Text('Retry',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.warning)),
                  ),
                ],
              ),
            ),
          // Category filter chips removed
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off,
                size: 56, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text('No products found', style: AppTheme.headingMedium),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView.builder(
        itemCount: _filtered.length,
        itemBuilder: (_, i) => ProductCard(
          product: _filtered[i],
          onTap: () => _onProductTap(_filtered[i]),
        ),
      ),
    );
  }
}
