import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

/// Admin customer management – full CRUD against the Supabase backend.
class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  List<Customer> _allCustomers = [];
  List<Customer> _filtered = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selectedCustomerIds = {};
  bool _isSelectionMode = false;

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

  void _toggleSelection(String customerId) {
    setState(() {
      if (_selectedCustomerIds.contains(customerId)) {
        _selectedCustomerIds.remove(customerId);
        if (_selectedCustomerIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedCustomerIds.add(customerId);
      }
    });
  }

  void _onTileLongPress(String customerId) {
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
        _selectedCustomerIds.add(customerId);
      });
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedCustomerIds.clear();
      _isSelectionMode = false;
    });
  }

  bool get _isAllSelected =>
      _filtered.isNotEmpty && _selectedCustomerIds.length == _filtered.length;

  void _toggleSelectAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedCustomerIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedCustomerIds.addAll(_filtered.map((c) => c.id));
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelectedCustomers() async {
    final count = _selectedCustomerIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Customers'),
        content: Text('Delete $count selected customer(s)? This action cannot be undone.'),
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

    final customerIdsToDelete = _selectedCustomerIds.toList();
    final result = await ApiService.bulkDeleteCustomers(customerIdsToDelete);
    if (!mounted) return;

    setState(() {
      _selectedCustomerIds.clear();
      _isSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          result.success ? '$count customers deleted.' : result.error ?? 'Failed to delete customers.'),
      backgroundColor: result.success ? AppTheme.success : AppTheme.error,
    ));

    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getCustomers();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _allCustomers = result.data!;
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
      _filtered = _allCustomers.where((c) {
        if (c.id == '00000000-0000-0000-0000-000000000000') return false;
        return query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            c.phone.contains(query) ||
            c.area.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _openForm([Customer? customer]) async {
    final saved = await showDialog<Customer?>(
      context: context,
      builder: (_) => _CustomerFormDialog(customer: customer),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(customer == null
            ? 'Customer "${saved.name}" created.'
            : 'Customer "${saved.name}" updated.'),
        backgroundColor: AppTheme.success,
      ));
      _loadCustomers();
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text(
            'Delete "${customer.name}"? This action cannot be undone.'),
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

    final result = await ApiService.deleteCustomer(customer.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? 'Customer "${customer.name}" deleted.'
          : result.error ?? ''),
      backgroundColor: result.success ? AppTheme.success : AppTheme.error,
    ));

    if (result.success) _loadCustomers();
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
            ? Text('${_selectedCustomerIds.length} selected')
            : Row(
                children: [
                  const Icon(Icons.people_alt_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Manage Customers',
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
                if (_selectedCustomerIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white),
                    tooltip: 'Delete Selected',
                    onPressed: _deleteSelectedCustomers,
                  ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.playlist_add_check),
                  tooltip: 'Select Customers',
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = true;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadCustomers,
                  tooltip: 'Refresh',
                ),
              ],
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
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Customer'),
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
                          Icon(Icons.person_search,
                              size: 56, color: AppTheme.textSecondary),
                          SizedBox(height: 12),
                          Text('No customers found',
                              style: AppTheme.headingMedium),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCustomers,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 84, top: 4),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final customer = _filtered[i];
                          final isSelected = _selectedCustomerIds.contains(customer.id);
                          return _CustomerTile(
                            customer: customer,
                            isSelected: isSelected,
                            isSelectionMode: _isSelectionMode,
                            onTap: () {
                              if (_isSelectionMode) {
                                _toggleSelection(customer.id);
                              } else {
                                _openForm(customer);
                              }
                            },
                            onLongPress: () => _onTileLongPress(customer.id),
                            onEdit: () => _openForm(customer),
                            onDelete: () => _deleteCustomer(customer),
                          );
                        },
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
              onPressed: _loadCustomers,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Customer tile
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CustomerTile({
    required this.customer,
    required this.onEdit,
    required this.onDelete,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
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
              CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                radius: 24,
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.headingSmall),
                    if (customer.phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(customer.phone, style: AppTheme.bodySmall),
                    ],
                    if (customer.address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(customer.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (customer.area.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.tableHeaderColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        customer.area,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit form dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerFormDialog extends StatefulWidget {
  final Customer? customer;

  const _CustomerFormDialog({this.customer});

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _addressCtrl = TextEditingController(text: c?.address ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Customer name is required');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final ApiResult<Customer> result;
    if (_isEdit) {
      final edited = Customer(
        id: widget.customer!.id,
        name: name,
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
      );
      result = await ApiService.updateCustomer(edited);
    } else {
      result = await ApiService.createCustomer(
        name: name,
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
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
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Customer' : 'Add Customer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_outlined, size: 20),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
          ],
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
              : Text(_isEdit ? 'Save Changes' : 'Add Customer'),
        ),
      ],
    );
  }
}