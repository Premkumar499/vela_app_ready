import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import '../widgets/bilingual_bill_dashboard.dart';

/// Bill History with two tabs:
///   1. Cash Bills  – simple bilingual customer receipt
///   2. Company Invoices – professional VELA AGENCY invoice
class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

enum _BillPeriod { today, month, year, all }

class _BillHistoryScreenState extends State<BillHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<Bill> _allBills = [];
  List<Bill> _filtered = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _error;
  _BillPeriod _period = _BillPeriod.all;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedBillNumbers = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkRole();
    _loadBills();
    _searchCtrl.addListener(_applyFilter);
  }

  Future<void> _checkRole() async {
    final session = await SessionService.getSession();
    if (mounted) {
      setState(() {
        _isAdmin = SessionService.isAdminSession(session);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBills() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getBills();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _allBills = result.data!;
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
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfMonth = DateTime(now.year, now.month);
    final startOfYear = DateTime(now.year);

    setState(() {
      _filtered = _allBills.where((b) {
        if (query.isNotEmpty &&
            !b.billNumber.toLowerCase().contains(query) &&
            !b.customerName.toLowerCase().contains(query)) {
          return false;
        }
        if (_period == _BillPeriod.all) return true;
        final d = DateTime.tryParse(b.date);
        if (d == null) return false;
        return switch (_period) {
          _BillPeriod.today => !d.isBefore(startOfDay),
          _BillPeriod.month => !d.isBefore(startOfMonth),
          _BillPeriod.year => !d.isBefore(startOfYear),
          _BillPeriod.all => true,
        };
      }).toList();
    });
  }

  void _toggleSelection(String billNumber) {
    setState(() {
      if (_selectedBillNumbers.contains(billNumber)) {
        _selectedBillNumbers.remove(billNumber);
        if (_selectedBillNumbers.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedBillNumbers.add(billNumber);
      }
    });
  }

  void _onTileLongPress(String billNumber) {
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
        _selectedBillNumbers.add(billNumber);
      });
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedBillNumbers.clear();
      _isSelectionMode = false;
    });
  }

  bool get _isAllSelected =>
      _filtered.isNotEmpty && _selectedBillNumbers.length == _filtered.length;

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedBillNumbers.clear();
        _isSelectionMode = false;
      } else {
        _selectedBillNumbers.addAll(_filtered.map((b) => b.billNumber));
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteBill(String billNumber) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Delete bill $billNumber? This action cannot be undone.'),
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

    final result = await ApiService.deleteBill(billNumber);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          result.success ? 'Bill $billNumber deleted.' : result.error ?? ''),
      backgroundColor: result.success ? AppTheme.success : AppTheme.error,
    ));

    if (result.success) _loadBills();
  }

  Future<void> _deleteSelectedBills() async {
    final count = _selectedBillNumbers.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Bills'),
        content: Text('Delete $count selected bill(s)? This action cannot be undone.'),
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

    final billNumbersToDelete = _selectedBillNumbers.toList();
    final result = await ApiService.bulkDeleteBills(billNumbersToDelete);
    if (!mounted) return;

    setState(() {
      _selectedBillNumbers.clear();
      _isSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          result.success ? '$count bills deleted.' : result.error ?? 'Failed to delete bills.'),
      backgroundColor: result.success ? AppTheme.success : AppTheme.error,
    ));

    _loadBills();
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
            ? Text('${_selectedBillNumbers.length} selected')
            : Row(
                children: [
                  const Icon(Icons.history, size: 20),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Bill History',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by bill number or customer…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
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
              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.receipt, size: 18),
                    text: 'User Bill',
                  ),
                  Tab(
                    icon: Icon(Icons.business_center, size: 18),
                    text: 'Company Bill',
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: Icon(_isAllSelected ? Icons.deselect : Icons.select_all),
                  tooltip: _isAllSelected ? 'Deselect All' : 'Select All',
                  onPressed: _toggleSelectAll,
                ),
                if (_isAdmin && _selectedBillNumbers.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    tooltip: 'Delete Selected',
                    onPressed: _deleteSelectedBills,
                  ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.playlist_add_check),
                  tooltip: 'Select Bills',
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = true;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadBills,
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildFilterCard(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBillList(isCashBill: true),
                          _buildBillList(isCashBill: false),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterCard() {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final total = _filtered.fold<double>(0, (s, b) => s + b.grandTotal);
    final periodLabel = switch (_period) {
      _BillPeriod.today => 'Today',
      _BillPeriod.month => 'This Month',
      _BillPeriod.year => 'This Year',
      _BillPeriod.all => 'All Time',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [BoxShadow(color: AppTheme.cardShadow, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period pills
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _BillPeriod.values) _buildPeriodPill(p),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // Summary row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  periodLabel,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text('${_filtered.length} bills',
                  style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              Text(
                currency.format(total),
                style: AppTheme.headingSmall.copyWith(
                    color: AppTheme.primaryDark, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodPill(_BillPeriod p) {
    final selected = _period == p;
    final label = switch (p) {
      _BillPeriod.today => 'Today',
      _BillPeriod.month => 'This Month',
      _BillPeriod.year => 'This Year',
      _BillPeriod.all => 'All',
    };
    return InkWell(
      onTap: () {
        setState(() => _period = p);
        _applyFilter();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.tableBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textSecondary,
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
              onPressed: _loadBills,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildBillList({required bool isCashBill}) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCashBill ? Icons.receipt_long : Icons.business_center,
              size: 64,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _allBills.isEmpty ? 'No bills saved yet.' : 'No results found.',
              style: AppTheme.headingMedium,
            ),
            if (_allBills.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('Create a new bill to see it here.',
                  style: AppTheme.bodySmall),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBills,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _filtered.length,
        itemBuilder: (_, i) {
          final bill = _filtered[i];
          final isSelected = _selectedBillNumbers.contains(bill.billNumber);
          return _BillTile(
            bill: bill,
            currency: currency,
            isCashBill: isCashBill,
            isAdmin: _isAdmin,
            isSelected: isSelected,
            isSelectionMode: _isSelectionMode,
            onTap: () {
              if (_isSelectionMode) {
                _toggleSelection(bill.billNumber);
              } else {
                Navigator.pushNamed(
                  context,
                  AppConstants.routeBillDetails,
                  arguments: {
                    'billNumber': bill.billNumber,
                    'isCompanyBill': !isCashBill,
                  },
                );
              }
            },
            onLongPress: () => _onTileLongPress(bill.billNumber),
            onDelete: () => _deleteBill(bill.billNumber),
            onView: () {
              if (isCashBill) {
                // Open bilingual cash bill receipt
                _openCashBill(bill);
              } else {
                // Open professional company invoice
                Navigator.pushNamed(
                  context,
                  '/company_invoice',
                  arguments: bill,
                );
              }
            },
          );
        },
      ),
    );
  }

  void _openCashBill(Bill bill) {
    // Build receipt data map matching BilingualBillDashboard format
    final dt = DateTime.tryParse(bill.date) ?? DateTime.now();
    final receiptData = {
      'invoice': {
        'bill_no': bill.billNumber,
        'date': DateFormat('dd/MM/yyyy').format(dt),
        'time': DateFormat('hh:mm a').format(dt),
      },
      'payment': {
        'method': bill.paymentType,
      },
      'items': bill.items
          .map((item) => {
                'product_name': item.productName,
                'qty': item.quantity,
                'rate': item.rate,
                'amount': item.total,
                'unit': item.unit,
              })
          .toList(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BilingualBillDashboard(
          receiptData: receiptData,
          onClose: () => Navigator.pop(context),
          autoSave: false,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bill Tile
// ─────────────────────────────────────────────────────────────────────────────

class _BillTile extends StatelessWidget {
  final Bill bill;
  final NumberFormat currency;
  final bool isCashBill;
  final bool isAdmin;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onView;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;

  const _BillTile({
    required this.bill,
    required this.currency,
    required this.isCashBill,
    required this.isAdmin,
    required this.onTap,
    required this.onDelete,
    required this.onView,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(bill.date);
    final paymentColor = bill.paymentType == 'Cash'
        ? AppTheme.success
        : bill.paymentType == 'Credit'
            ? AppTheme.warning
            : AppTheme.info;

    // Different accent for each section
    final accentColor = isCashBill ? AppTheme.success : AppTheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? accentColor : Colors.transparent,
          width: 1.5,
        ),
      ),
      color: isSelected ? accentColor.withValues(alpha: 0.05) : null,
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
                  activeColor: accentColor,
                ),
                const SizedBox(width: 4),
              ],
              // Bill number badge
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    bill.billNumber,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Bill info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            bill.billNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.headingSmall
                                .copyWith(color: accentColor),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: paymentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            bill.paymentType,
                            style: AppTheme.bodySmall.copyWith(
                              color: paymentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bill.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final calendarIcon = const Icon(Icons.calendar_today,
                            size: 12, color: AppTheme.textSecondary);
                        final itemsSegment = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_2_outlined,
                                size: 12, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text('${bill.itemCount} items',
                                style: AppTheme.bodySmall),
                          ],
                        );
                        // On very narrow tiles drop the item-count segment
                        // so the date line never overflows.
                        if (constraints.maxWidth < 240) {
                          return Row(
                            children: [
                              calendarIcon,
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  dateStr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodySmall,
                                ),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            calendarIcon,
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                dateStr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 12),
                            itemsSegment,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Grand total + actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currency.format(bill.grandTotal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppTheme.headingMedium.copyWith(color: accentColor),
                  ),
                  if (!isSelectionMode) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // View bill button – different icon per tab
                        IconButton(
                          icon: Icon(
                            isCashBill
                                ? Icons.receipt_long
                                : Icons.business_center,
                            color: accentColor,
                            size: 20,
                          ),
                          onPressed: onView,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          tooltip: isCashBill
                              ? 'View Cash Bill'
                              : 'View Company Invoice',
                        ),
                        if (isAdmin)
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.error, size: 20),
                            onPressed: onDelete,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            tooltip: 'Delete',
                          ),
                        const Icon(Icons.chevron_right,
                            color: AppTheme.textSecondary),
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

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy  HH:mm').format(dt);
    } catch (_) {
      return isoDate;
    }
  }
}

