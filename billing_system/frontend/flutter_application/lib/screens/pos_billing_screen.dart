import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../providers/billing_provider.dart';
import '../services/api_service.dart';
import '../utils/pos_theme.dart';
import '../widgets/pos_bill_item_row.dart';
import '../widgets/pos_payment_selector.dart';
import '../widgets/pos_product_card.dart';
import '../widgets/pos_summary_section.dart';
import '../widgets/bilingual_bill_dashboard.dart';
import '../models/invoice_model.dart';
import '../widgets/toast_notification.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class PosBillingScreen extends StatefulWidget {
  const PosBillingScreen({super.key});

  @override
  State<PosBillingScreen> createState() => _PosBillingScreenState();
}

class _PosBillingScreenState extends State<PosBillingScreen> {
  // ── Product state ────────────────────────────────────────────────────────
  List<Product> _allProducts    = [];
  List<Product> _filtered       = [];
  List<String>  _categories     = ['All'];
  String        _selectedCat    = 'All';
  bool          _loadingProds   = true;
  int           _productsToShow = 100;

  // ── Search ───────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // ── Bill state ───────────────────────────────────────────────────────────
  bool _isSaving = false;
  String _invoiceNum = 'DRAFT';

  void _showErrorMessage(String? msg) {
    if (msg != null && msg.isNotEmpty) {
      showToast(context, msg, isError: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadProducts() async {
    setState(() => _loadingProds = true);
    // Housekeeping: expire stale draft holds so abandoned draft stock is freed
    ApiService.expireStaleHolds();
    final result = await ApiService.getProducts();
    if (!mounted) return;
    if (result.success && result.data != null) {
      _allProducts = result.data!;
      _filtered    = _allProducts;
      final cats   = _allProducts.map((p) => p.category)
          .where((c) => c != 'Function Bill Products')
          .toSet().toList()..sort();
      _categories  = ['All', ...cats];
      _productsToShow = 100;
    }
    setState(() => _loadingProds = false);
  }

  void _applyFilter() {
    final q   = _searchCtrl.text.trim().toLowerCase();
    final cat = _selectedCat;
    setState(() {
      _productsToShow = 100;
      _filtered = _allProducts.where((p) {
        if (p.category == 'Function Bill Products') return false;
        final matchCat  = cat == 'All' || p.category == cat;
        final matchText = q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q);
        return matchCat && matchText;
      }).toList();
    });
  }

  void _selectCategory(String cat) {
    setState(() => _selectedCat = cat);
    _applyFilter();
  }

  // ─── Bill actions ──────────────────────────────────────────────────────────
  Future<void> _saveBill() async {
    final prov = context.read<BillingProvider>();
    if (!prov.canSave) {
      _snack('Add at least one item to save.', error: true);
      return;
    }
    if (prov.customer.id == '00000000-0000-0000-0000-000000000000' ||
        prov.customer.name == 'Walk-in Customer') {
      _snack('Please select a customer or add a new customer first', error: true);
      return;
    }
    setState(() => _isSaving = true);
    final result = await ApiService.saveBill(
      customer:    prov.customer,
      items:       prov.items,
      paymentType: prov.paymentType,
      customerPhone: prov.customerPhone,
      salesType:   prov.salesType,
      remarks:     prov.remarks,
      through:     prov.through,
      area:        prov.area,
      priceList:   prov.priceList,
      draftBillId: prov.draftBillId,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      final billNum = result.data?['bill_number'] as String? ?? 'SAVED';
      setState(() => _invoiceNum = billNum);

      // Build receipt JSON from current bill state
      final now = DateTime.now();
      final receiptData = {
        'company': {
          'name':    Invoice.companyName,
          'address': Invoice.companyAddress,
        },
        'invoice': {
          'bill_no':      billNum,
          'invoice_type': 'NON_GST',
          'date': '${now.day.toString().padLeft(2,'0')}/'
                  '${now.month.toString().padLeft(2,'0')}/'
                  '${now.year}',
          'time': _formatTime(now),
        },
        'customer': {
          'name': prov.customer.name,
        },
        'items': prov.items.map((item) => {
          'product_name': item.productName,
          'brand':        '',
          'qty':          item.quantity % 1 == 0
                            ? item.quantity.toInt()
                            : item.quantity,
          'unit':         item.unit,
          'rate':         item.rate.toStringAsFixed(2),
          'amount':       item.total.toStringAsFixed(2),
        }).toList(),
        'summary': {
          'total_qty': prov.items.fold<num>(
              0, (s, i) => s + (i.quantity % 1 == 0 ? i.quantity.toInt() : i.quantity)),
          'total':     prov.grandTotal.toStringAsFixed(2),
        },
        'payment': {
          'method': prov.paymentType,
        },
      };

      // Show bilingual bill dashboard
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => Dialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
                child: BilingualBillDashboard(
                  receiptData: receiptData,
                  onClose: () {
                    Navigator.of(dialogCtx).pop();
                    prov.resetBill();
                    setState(() {
                      _invoiceNum = 'DRAFT';
                    });
                    _showErrorMessage(null);
                  },
                ),
              ),
            ),
          ),
        );
      }
    } else {
      _snack(result.error ?? 'Failed to save bill.', error: true);
    }
  }

  String _formatTime(DateTime dt) {
    final h   = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m   = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  void _cancelBill() {
    final prov = context.read<BillingProvider>();
    if (prov.itemCount == 0) return;
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title:   'Cancel Bill',
        message: 'Clear all items and cancel this bill?',
        danger:  true,
        onConfirm: () {
          prov.cancelBillWithRelease();
          setState(() {
            _invoiceNum = 'DRAFT';
          });
          _showErrorMessage(null);
        },
      ),
    );
  }

  void _newBill() {
    final prov = context.read<BillingProvider>();
    if (prov.itemCount == 0) return;
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title:   'New Bill',
        message: 'Discard current bill and start a new one?',
        onConfirm: () {
          prov.cancelBillWithRelease();
          setState(() {
            _invoiceNum = 'DRAFT';
          });
          _showErrorMessage(null);
        },
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    showToast(context, msg, isError: error);
  }

  Future<bool> _confirmExit() async {
    final prov = context.read<BillingProvider>();
    if (prov.itemCount == 0) {
      return true;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Exit Billing',
        message: 'You have active items in your cart. Leaving this screen will cancel the current bill and release all reserved stock. Exit anyway?',
        danger: true,
        onConfirm: () {
          Navigator.of(context).pop(true);
        },
      ),
    );
    if (discard == true) {
      await prov.cancelBillWithRelease();
      return true;
    }
    return false;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillingProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        // Custom AppBar back action for mobile checkout screen
        final leadingWidget = Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
                onPressed: () async {
                  final shouldPop = await _confirmExit();
                  if (shouldPop && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                tooltip: 'Back',
              )
            : Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(PosTheme.radiusSm),
                  ),
                  child: const Icon(Icons.point_of_sale,
                      color: Colors.white, size: 20),
                ),
              );

        final appBarTitle = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ERP Billing',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            Text('New Bill · ${provider.customer.name}',
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        );

        final leftContent = _LeftPanel(
          categories:   _categories,
          selectedCat:  _selectedCat,
          products:     _filtered.take(_productsToShow).toList(),
          loading:      _loadingProds,
          searchCtrl:   _searchCtrl,
          searchFocus:  _searchFocus,
          onCategory:   _selectCategory,
          hasMore:      _productsToShow < _filtered.length,
          onLoadMore:   () {
            setState(() => _productsToShow += 100);
          },
          onProduct:    (p) async {
            final result = await provider.addProductWithReservation(p);
            if (!context.mounted) return;
            if (!result.success) {
              final available = result.remainingAvailable;
              final msg = available > 0
                  ? 'Only ${available.toStringAsFixed(available.truncateToDouble() == available ? 0 : 1)} units are currently available'
                  : '${p.name} is out of stock';
              _showErrorMessage(msg);
            } else {
              _showErrorMessage(null);
            }
          },
        );

        final rightContent = _RightPanel(
          provider:   provider,
          invoiceNum: _invoiceNum,
          isSaving:   _isSaving,
          onSave:     _saveBill,
          onCancel:   _cancelBill,
          scrollable: !isWide || constraints.maxHeight < 700,
          isMobileCheckout: false,
          onError: (msg) {
            _showErrorMessage(msg.isEmpty ? null : msg);
          },
        );

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldPop = await _confirmExit();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            backgroundColor: PosTheme.background,
            appBar: AppBar(
              backgroundColor: PosTheme.primary,
              elevation: 0,
              leading: leadingWidget,
              title: appBarTitle,
              actions: [
                TextButton.icon(
                  onPressed: _newBill,
                  icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.white70),
                  label: const Text('New Bill',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 65, child: leftContent),
                      Expanded(flex: 35, child: rightContent),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 50, child: leftContent),
                      const VerticalDivider(width: 1, thickness: 1, color: PosTheme.border),
                      Expanded(flex: 50, child: rightContent),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEFT PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _LeftPanel extends StatelessWidget {
  final List<String>  categories;
  final String        selectedCat;
  final List<Product> products;
  final bool          loading;
  final TextEditingController searchCtrl;
  final FocusNode             searchFocus;
  final ValueChanged<String>  onCategory;
  final ValueChanged<Product> onProduct;
  final bool                  hasMore;
  final VoidCallback          onLoadMore;

  const _LeftPanel({
    required this.categories,
    required this.selectedCat,
    required this.products,
    required this.loading,
    required this.searchCtrl,
    required this.searchFocus,
    required this.onCategory,
    required this.onProduct,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final pad = isMobile ? PosTheme.padSm : PosTheme.padLg;

    return Column(
      children: [
        // ── Search bar + filter row ────────────────────────────────────
        Container(
          color: PosTheme.surface,
          padding: EdgeInsets.fromLTRB(
            pad, PosTheme.padMd,
            pad, 0,
          ),
          child: _SearchBar(controller: searchCtrl, focusNode: searchFocus),
        ),
        _CategoryChips(
          categories: categories,
          selected: selectedCat,
          onSelected: onCategory,
          horizontalPadding: pad,
        ),
        const Divider(height: 1, color: PosTheme.border),
        // ── Product grid ───────────────────────────────────────────────
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : products.isEmpty
                  ? _EmptyProducts(hasSearch: searchCtrl.text.isNotEmpty)
                  : _ProductGrid(
                      products: products,
                      onTap: onProduct,
                      hasMore: hasMore,
                      onLoadMore: onLoadMore,
                    ),
        ),
      ],
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _SearchBar({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:  controller,
      focusNode:   focusNode,
      autofocus:   false,
      style:       PosTheme.body,
      decoration: InputDecoration(
        hintText:    'Search Products...',
        prefixIcon:  const Icon(Icons.search_rounded, color: PosTheme.textHint, size: 20),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) => value.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: PosTheme.textHint),
                  onPressed: controller.clear,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

// ─── Category chips ────────────────────────────────────────────────────────────
class _CategoryChips extends StatelessWidget {
  final List<String>         categories;
  final String               selected;
  final ValueChanged<String> onSelected;
  final double               horizontalPadding;

  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.horizontalPadding = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: PosTheme.surface,
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: horizontalPadding),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat    = categories[i];
          final active = cat == selected;
          return InkWell(
            onTap: () => onSelected(cat),
            borderRadius: BorderRadius.circular(PosTheme.radiusSm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? PosTheme.primary : PosTheme.surface,
                borderRadius: BorderRadius.circular(PosTheme.radiusSm),
                border: Border.all(
                  color: active ? PosTheme.primary : const Color(0xFFCDD3DC),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active) ...[
                    const Icon(
                      Icons.check,
                      color: Color(0xFF1B5E20),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    cat,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.bold : FontWeight.w600,
                      color: active ? Colors.white : PosTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Product grid ──────────────────────────────────────────────────────────────
class _ProductGrid extends StatefulWidget {
  final List<Product>         products;
  final ValueChanged<Product> onTap;
  final bool                  hasMore;
  final VoidCallback          onLoadMore;

  const _ProductGrid({
    required this.products,
    required this.onTap,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  State<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends State<_ProductGrid> {
  late ScrollController _scrollController;
  bool _isLoadingMore = false;

  // Each card is exactly this tall — hard pixel cap, no aspect ratio math.
  static const double _cardH = 110.0;
  static const double _gap   = 8.0;
  static const double _pad   = 12.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.hasMore || _isLoadingMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      setState(() {
        _isLoadingMore = true;
      });
      // Simulate a small premium loading delay (e.g. 500ms) for UI feedback
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          widget.onLoadMore();
          setState(() {
            _isLoadingMore = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth - _pad * 2;
        final cols   = availW < 380 ? 1 : availW < 580 ? 2 : availW < 820 ? 3 : 4;
        final colW   = (availW - _gap * (cols - 1)) / cols;

        // Build rows of [cols] items each
        final rows = <List<Product>>[];
        for (var i = 0; i < widget.products.length; i += cols) {
          rows.add(widget.products.sublist(i, (i + cols).clamp(0, widget.products.length)));
        }

        final itemCount = rows.length + (widget.hasMore ? 1 : 0);

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(_pad),
          itemCount: itemCount,
          itemBuilder: (_, rowIdx) {
            if (rowIdx == rows.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PosTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading more products...',
                        style: TextStyle(
                          fontSize: 13,
                          color: PosTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final row = rows[rowIdx];
            return Padding(
              padding: EdgeInsets.only(
                  bottom: rowIdx < rows.length - 1 || widget.hasMore ? _gap : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var ci = 0; ci < cols; ci++) ...[
                    if (ci < row.length)
                      Builder(
                        builder: (ctx) {
                          final product = row[ci];
                          final provider = ctx.watch<BillingProvider>();
                          
                          int cartIdx = -1;
                          for (int idx = 0; idx < provider.items.length; idx++) {
                            if (provider.items[idx].productId == product.id) {
                              cartIdx = idx;
                              break;
                            }
                          }
                          final cartQty = cartIdx != -1 ? provider.items[cartIdx].quantity : 0;
                          
                          return SizedBox(
                            width: colW,
                            height: _cardH,
                            child: PosProductCard(
                              product: product,
                              onTap:   () => widget.onTap(product),
                              cartQuantity: cartQty,
                              onIncrease: () async {
                                final result = await provider.addProductWithReservation(product, quantity: 1);
                                if (!result.success && ctx.mounted) {
                                  final avail = result.remainingAvailable;
                                  final msg = avail > 0
                                      ? 'Only ${avail.toStringAsFixed(0)} units available'
                                      : '${product.name} is out of stock';
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                    content: Text(msg),
                                    backgroundColor: PosTheme.danger,
                                    duration: const Duration(seconds: 3),
                                  ));
                                }
                              },
                              onDecrease: () async {
                                if (cartIdx != -1) {
                                  final item = provider.items[cartIdx];
                                  if (item.quantity > 1) {
                                    await provider.updateQuantityWithReservation(
                                        cartIdx, item.quantity - 1, product);
                                  } else {
                                    await provider.removeItemWithRelease(cartIdx);
                                  }
                                }
                              },
                            ),
                          );
                        }
                      )
                    else
                      SizedBox(width: colW, height: _cardH), // empty filler
                    if (ci < cols - 1) const SizedBox(width: _gap),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  final bool hasSearch;
  const _EmptyProducts({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off_rounded : Icons.inventory_2_outlined,
            size: 64, color: PosTheme.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No products match your search' : 'No products available',
            style: PosTheme.bodyBold.copyWith(color: PosTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _RightPanel extends StatelessWidget {
  final BillingProvider provider;
  final String invoiceNum;
  final bool   isSaving;
  final Future<void> Function() onSave;
  final VoidCallback onCancel;
  final ValueChanged<String>? onError;

  /// On narrow screens the panel is squeezed into a fraction of the screen
  /// height, so the whole panel scrolls instead of overflowing.
  final bool scrollable;
  final bool isMobileCheckout;

  const _RightPanel({
    required this.provider,
    required this.invoiceNum,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
    this.scrollable = false,
    this.isMobileCheckout = false,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    // ── Bill items list ────────────────────────────────────────────────
    final itemsList = provider.items.isEmpty
        ? const PosEmptyCartPlaceholder()
        : ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: scrollable || isMobileCheckout,
            physics: (scrollable || isMobileCheckout)
                ? const NeverScrollableScrollPhysics()
                : null,
            itemCount: provider.items.length,
            itemBuilder: (ctx, i) {
              final item = provider.items[i];
              // We need the Product to call reservation-aware methods.
              // Build a lightweight proxy Product from the BillItem.
              final proxyProduct = Product(
                id:       item.productId,
                name:     item.productName,
                unit:     item.unit,
                price:    item.rate,
                mrp:      item.rate,
                stock:    item.maxStock,
                category: '',
              );
              return PosBillItemRow(
                index: i,
                item:  item,
                onIncrease: () async {
                  final result =
                      await provider.addProductWithReservation(
                          proxyProduct, quantity: 1);
                  if (!result.success && ctx.mounted) {
                    final avail = result.remainingAvailable;
                    final msg = avail > 0
                        ? 'Only ${avail.toStringAsFixed(0)} units available'
                        : '${item.productName} is out of stock';
                    if (onError != null) {
                      onError!(msg);
                    } else {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(msg),
                        backgroundColor: PosTheme.danger,
                        duration: const Duration(seconds: 3),
                      ));
                    }
                  } else if (result.success && onError != null) {
                    onError!('');
                  }
                },
                onDecrease: () async {
                  if (item.quantity > 1) {
                    await provider.updateQuantityWithReservation(
                        i, item.quantity - 1, proxyProduct);
                  } else {
                    await provider.removeItemWithRelease(i);
                  }
                },
                onDelete: () => provider.removeItemWithRelease(i),
              );
            },
          );

    if (isMobileCheckout) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Bill header ─────────────────────────────────────────────
                  _BillHeader(
                    invoiceNum:  invoiceNum,
                    customerName: provider.customer.name,
                    itemCount:   provider.itemCount,
                    paymentType: provider.paymentType,
                  ),
                  // ── Customer details input ─────────────────────────────────
                  _CustomerDetailsInput(provider: provider),
                  // ── Bill items list ────────────────────────────────────────
                  itemsList,
                  // ── Summary ────────────────────────────────────────────────
                  PosSummarySection(
                    subtotal:   provider.subtotal,
                    grandTotal: provider.grandTotal,
                  ),
                  // ── Payment selector ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: PosTheme.padSm),
                    child: PosPaymentSelector(
                      selected:  provider.paymentType,
                      onChanged: provider.setPaymentType,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Sticky Action buttons ──
          _ActionButtons(
            isSaving:  isSaving,
            canSave:   provider.canSave,
            onComplete: onSave,
            onCancel:  onCancel,
          ),
        ],
      );
    }

    final panel = Column(
      children: [
        // ── Bill header ─────────────────────────────────────────────
        _BillHeader(
          invoiceNum:  invoiceNum,
          customerName: provider.customer.name,
          itemCount:   provider.itemCount,
          paymentType: provider.paymentType,
        ),
        // ── Customer details input ─────────────────────────────────
        _CustomerDetailsInput(provider: provider),
        // ── Column labels ──────────────────────────────────────────
        if (MediaQuery.of(context).size.width >= 600) _BillTableHeader(),
        // ── Bill items list ────────────────────────────────────────
        if (scrollable)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.width < 600 ? 140.0 : 260.0,
            ),
            child: itemsList,
          )
        else
          Expanded(child: itemsList),
        // ── Summary ────────────────────────────────────────────────
        PosSummarySection(
          subtotal:   provider.subtotal,
          grandTotal: provider.grandTotal,
        ),
        // ── Payment selector ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(
            top: PosTheme.padSm,
            bottom: PosTheme.padSm,
          ),
          child: PosPaymentSelector(
            selected:  provider.paymentType,
            onChanged: provider.setPaymentType,
          ),
        ),
        // ── Action buttons ─────────────────────────────────────────
        _ActionButtons(
          isSaving:  isSaving,
          canSave:   provider.canSave,
          onComplete: onSave,
          onCancel:  onCancel,
        ),
      ],
    );

    if (!scrollable) {
      return Container(decoration: PosTheme.rightPanel, child: panel);
    }

    // Narrow screens: the whole panel scrolls so it never overflows the
    // reduced height. The items list stays open inside (bounded height).
    return Container(
      decoration: PosTheme.rightPanel,
      child: SingleChildScrollView(
        child: Column(
          children: [
            panel,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Bill header ──────────────────────────────────────────────────────────────
class _BillHeader extends StatelessWidget {
  final String invoiceNum;
  final String customerName;
  final int    itemCount;
  final String paymentType;

  const _BillHeader({
    required this.invoiceNum,
    required this.customerName,
    required this.itemCount,
    required this.paymentType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFEBF6ED),
        border: Border(bottom: BorderSide(color: Color(0xFFC8E6C9))),
      ),
      child: Row(
        children: [
          // Green Card Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          // Invoice/Draft text
          Expanded(
            child: Text(
              invoiceNum,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E7D32),
              ),
            ),
          ),
          // Item count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCDFE4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$itemCount items',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bill table header ────────────────────────────────────────────────────────
class _BillTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosTheme.padMd, vertical: 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F8E9),
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 22 + 8), // row num spacer
          Expanded(
            flex: 4,
            child: Text('ITEM',
                style: PosTheme.caption.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          Expanded(
            flex: 3,
            child: Text('QTY',
                textAlign: TextAlign.center,
                style: PosTheme.caption.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          Expanded(
            flex: 2,
            child: Text('RATE',
                textAlign: TextAlign.right,
                style: PosTheme.caption.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          Expanded(
            flex: 2,
            child: Text('AMT',
                textAlign: TextAlign.right,
                style: PosTheme.caption.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          const SizedBox(width: 36), // delete btn spacer
        ],
      ),
    );
  }
}

// ─── Action buttons ───────────────────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final bool isSaving;
  final bool canSave;
  final Future<void> Function() onComplete;
  final VoidCallback onCancel;

  const _ActionButtons({
    required this.isSaving,
    required this.canSave,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    Widget cancelBtn;
    Widget saveBtn;

    if (isNarrow) {
      cancelBtn = OutlinedButton(
        onPressed: canSave ? onCancel : null,
        style: PosTheme.dangerButton().copyWith(
          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
        ),
        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
      );

      saveBtn = ElevatedButton(
        onPressed: canSave && !isSaving ? onComplete : null,
        style: PosTheme.successButton().copyWith(
          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
        ),
        child: isSaving
            ? const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text('Complete', style: TextStyle(fontSize: 12)),
      );
    } else {
      cancelBtn = OutlinedButton.icon(
        onPressed: canSave ? onCancel : null,
        style: PosTheme.dangerButton(),
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('Cancel'),
      );

      saveBtn = ElevatedButton.icon(
        onPressed: canSave && !isSaving ? onComplete : null,
        style: PosTheme.successButton(),
        icon: isSaving
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_circle_outline_rounded, size: 18),
        label: Text(isSaving ? 'Saving…' : 'Complete'),
      );
    }

    return Container(
      padding: EdgeInsets.all(isNarrow ? PosTheme.padSm : PosTheme.padMd),
      decoration: const BoxDecoration(
        color: PosTheme.surface,
        border: Border(top: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: cancelBtn),
          SizedBox(width: isNarrow ? 6 : 8),
          Expanded(flex: 3, child: saveBtn),
        ],
      ),
    );
  }
}

// ─── Customer Details Input ───────────────────────────────────────────────────
class _CustomerDetailsInput extends StatefulWidget {
  final BillingProvider provider;

  const _CustomerDetailsInput({required this.provider});

  @override
  State<_CustomerDetailsInput> createState() => _CustomerDetailsInputState();
}

class _CustomerDetailsInputState extends State<_CustomerDetailsInput> {
  final TextEditingController _nameCtrl  = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();

  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  List<Customer> _allCustomers = [];
  List<Customer> _suggestions = [];

  @override
  void initState() {
    super.initState();
    final c = widget.provider.customer;
    if (c.name != 'Walk-in Customer') _nameCtrl.text = c.name;
    _phoneCtrl.text = widget.provider.customerPhone;
    _loadCustomers();
    _nameFocus.addListener(_onFocusChange);
    _phoneFocus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_CustomerDetailsInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final c = widget.provider.customer;
    if (_nameCtrl.text != c.name) {
      _nameCtrl.text = c.name == 'Walk-in Customer' ? '' : c.name;
    }
    if (_phoneCtrl.text != widget.provider.customerPhone) {
      _phoneCtrl.text = widget.provider.customerPhone;
    }
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onFocusChange);
    _phoneFocus.removeListener(_onFocusChange);
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _hideSuggestions();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final result = await ApiService.getCustomers();
    if (result.success && result.data != null) {
      if (mounted) {
        setState(() {
          _allCustomers = result.data!;
        });
      }
    }
  }

  void _onFocusChange() {
    if (_nameFocus.hasFocus || _phoneFocus.hasFocus) {
      _updateSuggestions();
    } else {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_nameFocus.hasFocus && !_phoneFocus.hasFocus) {
          _hideSuggestions();
        }
      });
    }
  }

  void _updateSuggestions() {
    final nameQ = _nameCtrl.text.trim().toLowerCase();
    final phoneQ = _phoneCtrl.text.trim().toLowerCase();

    if (nameQ.isEmpty && phoneQ.isEmpty) {
      _suggestions = [];
      _hideSuggestions();
      return;
    }

    _suggestions = _allCustomers.where((c) {
      final matchesName = nameQ.isEmpty || c.name.toLowerCase().contains(nameQ);
      final matchesPhone = phoneQ.isEmpty || c.phone.toLowerCase().contains(phoneQ);
      return matchesName && matchesPhone;
    }).toList();

    if (_suggestions.isNotEmpty && (_nameFocus.hasFocus || _phoneFocus.hasFocus)) {
      _showSuggestionsOverlay();
    } else {
      _hideSuggestions();
    }
  }

  void _showSuggestionsOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _layerLink.leaderSize?.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, _layerLink.leaderSize?.height ?? 44),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, index) {
                    final customer = _suggestions[index];
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _nameCtrl.text = customer.name;
                          _phoneCtrl.text = customer.phone;
                        });
                        widget.provider.setCustomer(customer);
                        widget.provider.setCustomerPhone(customer.phone);
                        _nameFocus.unfocus();
                        _phoneFocus.unfocus();
                        _hideSuggestions();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFFE8F5E9),
                              radius: 14,
                              child: Text(
                                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.name,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                  ),
                                  if (customer.phone.isNotEmpty)
                                    Text(
                                      customer.phone,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideSuggestions() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _openNewCustomerForm({String? initialName, String? initialPhone}) async {
    final nameCtrl    = TextEditingController(text: initialName);
    final phoneCtrl   = TextEditingController(text: initialPhone);
    final addressCtrl = TextEditingController();
    bool saving = false;

    final created = await showDialog<Customer>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 16,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: StatefulBuilder(
            builder: (ctx, setDlg) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEBF6ED),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_add_rounded,
                        color: Color(0xFF2E7D32),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'New Customer',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Name Field
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Customer Name *',
                    labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    hintText: 'Enter name',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF64748B), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // Phone Field
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    hintText: 'Enter phone number',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF64748B), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                // Address Field
                TextField(
                  controller: addressCtrl,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    labelText: 'Address',
                    labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    hintText: 'Enter address',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF64748B), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 28),
                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF64748B),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                if (name.isEmpty) return;
                                setDlg(() => saving = true);
                                final result = await ApiService.createCustomer(
                                  name:    name,
                                  phone:   phoneCtrl.text.trim(),
                                  email:   '',
                                  address: addressCtrl.text.trim(),
                                );
                                if (!ctx.mounted) return;
                                if (result.success) {
                                  Navigator.pop(ctx, result.data);
                                } else {
                                  setDlg(() => saving = false);
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                    content: Text(result.error ?? 'Failed to save customer'),
                                    backgroundColor: PosTheme.danger,
                                  ));
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Save Customer',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();

    if (created != null && mounted) {
      setState(() {
        _nameCtrl.text  = created.name;
        _phoneCtrl.text = created.phone;
      });
      widget.provider.setCustomer(created);
      widget.provider.setCustomerPhone(created.phone);
      _loadCustomers();
    }
  }

  Future<void> _openCustomerPicker({String? initialQuery}) async {
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerPickerSheet(initialQuery: initialQuery),
    );

    if (selected == null || !mounted) return;

    // "new" sentinel — open form to create customer in DB
    if (selected.id == '-1') {
      await _openNewCustomerForm(
        initialName: _nameCtrl.text,
        initialPhone: _phoneCtrl.text,
      );
      return;
    }

    setState(() {
      _nameCtrl.text  = selected.name;
      _phoneCtrl.text = selected.phone;
    });
    widget.provider.setCustomer(selected);
    widget.provider.setCustomerPhone(selected.phone);
    _loadCustomers();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: PosTheme.border)),
        ),
        child: isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Customer Name Input ──────────────────────────────────
                  SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Customer Name',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        suffixIcon: IconButton(
                          onPressed: () => _openCustomerPicker(
                            initialQuery: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : _phoneCtrl.text,
                          ),
                          icon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 16,
                          tooltip: 'Search Customer',
                        ),
                      ),
                      onChanged: (val) {
                        final current = widget.provider.customer;
                        widget.provider.setCustomer(Customer(
                          id: current.id,
                          name: val,
                          phone: current.phone,
                          address: current.address,
                          area: current.area,
                          gstin: current.gstin,
                          creditLimit: current.creditLimit,
                          balance: current.balance,
                        ));
                        _updateSuggestions();
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  // ── Phone Input ─────────────────────────────────────────
                  SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _phoneCtrl,
                      focusNode: _phoneFocus,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Phone',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        suffixIcon: IconButton(
                          onPressed: () => _openNewCustomerForm(
                            initialName: _nameCtrl.text,
                            initialPhone: _phoneCtrl.text,
                          ),
                          icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF2E7D32), size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 16,
                          tooltip: 'Add New Customer',
                        ),
                      ),
                      onChanged: (val) {
                        widget.provider.setCustomerPhone(val);
                        final current = widget.provider.customer;
                        widget.provider.setCustomer(Customer(
                          id: current.id,
                          name: current.name,
                          phone: val,
                          address: current.address,
                          area: current.area,
                          gstin: current.gstin,
                          creditLimit: current.creditLimit,
                          balance: current.balance,
                        ));
                        _updateSuggestions();
                      },
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  // ── Add New Customer Button (Left Side) ──────────────────────────
                  IconButton(
                    onPressed: () => _openNewCustomerForm(
                      initialName: _nameCtrl.text,
                      initialPhone: _phoneCtrl.text,
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF2E7D32), size: 20),
                    tooltip: 'Add New Customer',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(right: 8),
                  ),
                  
                  // ── Customer Name Input ──────────────────────────────────
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _nameCtrl,
                        focusNode: _nameFocus,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Customer Name',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF64748B), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (val) {
                          final current = widget.provider.customer;
                          widget.provider.setCustomer(Customer(
                            id: current.id,
                            name: val,
                            phone: current.phone,
                            address: current.address,
                            area: current.area,
                            gstin: current.gstin,
                            creditLimit: current.creditLimit,
                            balance: current.balance,
                          ));
                          _updateSuggestions();
                        },
                      ),
                    ),
                  ),
                  
                  // ── Search Icon Button ──────────────────────────────────
                  IconButton(
                    onPressed: () => _openCustomerPicker(
                      initialQuery: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : _phoneCtrl.text,
                    ),
                    icon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                    tooltip: 'Search Customer',
                  ),
                  
                  // ── Phone Input ─────────────────────────────────────────
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _phoneCtrl,
                        focusNode: _phoneFocus,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Phone',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                          prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF64748B), size: 18),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (val) {
                          widget.provider.setCustomerPhone(val);
                          final current = widget.provider.customer;
                          widget.provider.setCustomer(Customer(
                            id: current.id,
                            name: current.name,
                            phone: val,
                            address: current.address,
                            area: current.area,
                            gstin: current.gstin,
                            creditLimit: current.creditLimit,
                            balance: current.balance,
                          ));
                          _updateSuggestions();
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Customer Picker Bottom Sheet ─────────────────────────────────────────────
class _CustomerPickerSheet extends StatefulWidget {
  final String? initialQuery;
  const _CustomerPickerSheet({this.initialQuery});

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Customer> _all      = [];
  List<Customer> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _searchCtrl.text = widget.initialQuery!;
    }
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ApiService.getCustomers();
    if (!mounted) return;
    setState(() {
      _all      = result.data ?? [];
      _filtered = _all;
      _loading  = false;
    });
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.phone.contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // Reserve space for keyboard; never overflow the screen
    final maxH = (screenH * 0.75 - bottomInset).clamp(300.0, screenH * 0.85);
    return Container(
      height: maxH,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: PosTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text('Select Customer',
                    style: PosTheme.subtitle.copyWith(fontSize: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: PosTheme.body,
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon: const Icon(Icons.search_rounded,
                    size: 20, color: PosTheme.textHint),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _searchCtrl.clear,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PosTheme.radiusSm),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const Divider(height: 1, color: PosTheme.border),
          // New Customer option
          ListTile(
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: PosTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_add_alt_1_rounded,
                  color: PosTheme.primary, size: 20),
            ),
            title: const Text('New Customer',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: PosTheme.primary)),
            subtitle: const Text('Enter customer details manually'),
            onTap: () => Navigator.pop(
              context,
              Customer(id: '-1', name: '', phone: '',
                  address: '', area: '', gstin: '',
                  creditLimit: 0, balance: 0),
            ),
          ),
          const Divider(height: 1, color: PosTheme.border),
          // Customer list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text('No customers found',
                            style: PosTheme.body.copyWith(
                                color: PosTheme.textSecondary)),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final c = _filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  PosTheme.primary.withValues(alpha: 0.12),
                              radius: 18,
                              child: Text(
                                c.name.isNotEmpty
                                    ? c.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: PosTheme.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            title: Text(c.name,
                                style: PosTheme.bodyBold
                                    .copyWith(fontSize: 13)),
                            subtitle: c.phone.isNotEmpty
                                ? Text(c.phone, style: PosTheme.small)
                                : null,
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIRM DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool danger;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.onConfirm,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PosTheme.radiusLg)),
      title: Text(title, style: PosTheme.subtitle),
      content: Text(message, style: PosTheme.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          style: danger
              ? ElevatedButton.styleFrom(backgroundColor: PosTheme.danger)
              : PosTheme.primaryButton(height: 40),
          child: Text(danger ? 'Yes, Cancel' : 'Confirm'),
        ),
      ],
    );
  }
}
