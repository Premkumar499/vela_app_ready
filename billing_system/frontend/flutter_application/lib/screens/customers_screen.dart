import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';
import '../widgets/customer_card.dart';

/// Customer listing screen.
/// When [isPicker] is true, tapping returns the selected customer to the caller.
class CustomersScreen extends StatefulWidget {
  final bool isPicker;
  final Customer? currentCustomer;

  const CustomersScreen({
    super.key,
    this.isPicker = false,
    this.currentCustomer,
  });

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Customer> _allCustomers = [];
  List<Customer> _filtered = [];
  bool _isLoading = true;
  bool _isOffline = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    final result = await ApiService.getCustomers();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _allCustomers = result.data!;
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
      _filtered = _allCustomers.where((c) {
        if (c.id == '00000000-0000-0000-0000-000000000000') return false;
        return query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            c.phone.contains(query) ||
            c.area.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _onCustomerTap(Customer customer) {
    if (widget.isPicker) {
      Navigator.pop(context, customer);
    } else {
      _showCustomerDetail(customer);
    }
  }

  void _showCustomerDetail(Customer customer) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary,
                  radius: 28,
                  child: Text(
                    customer.name.isNotEmpty
                        ? customer.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.name, style: AppTheme.headingMedium),
                      if (customer.area.isNotEmpty)
                        Text(customer.area, style: AppTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            if (customer.phone.isNotEmpty)
              _DetailRow(Icons.phone, 'Phone', customer.phone),
            if (customer.email != null && customer.email!.isNotEmpty)
              _DetailRow(Icons.email_outlined, 'Email', customer.email!),
            if (customer.address.isNotEmpty)
              _DetailRow(Icons.location_on_outlined, 'Address', customer.address),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPicker ? 'Select Customer' : 'Customers'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or area…',
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
          if (_isOffline)
            Container(
              width: double.infinity,
              color: AppTheme.warning.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Backend unreachable — showing local demo data',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadCustomers,
                    child: const Text(
                      'Retry',
                      style: TextStyle(fontSize: 12, color: AppTheme.warning),
                    ),
                  ),
                ],
              ),
            ),
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
            Icon(Icons.person_search, size: 56, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text('No customers found', style: AppTheme.headingMedium),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCustomers,
      child: ListView.builder(
        itemCount: _filtered.length,
        itemBuilder: (_, i) {
          final customer = _filtered[i];
          final isSelected = widget.currentCustomer?.id == customer.id;
          return CustomerCard(
            customer: customer,
            isSelected: isSelected,
            onTap: () => _onCustomerTap(customer),
          );
        },
      ),
    );
  }
}

// ── Detail row helper ─────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary, fontSize: 11)),
                Text(value, style: AppTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
