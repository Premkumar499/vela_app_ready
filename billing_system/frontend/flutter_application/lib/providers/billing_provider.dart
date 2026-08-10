import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/bill_item.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

// Result of an addProduct reservation attempt
class ReservationResult {
  final bool success;
  final String? errorCode;
  final String message;
  /// How many units are actually available (used for user-facing error message)
  final double remainingAvailable;

  const ReservationResult({
    required this.success,
    this.errorCode,
    this.message = '',
    this.remainingAvailable = 0,
  });
}

/// Central state manager for the billing flow — no GST.
/// Integrates with the shared stock reservation system so that
/// stock is atomically reserved in the database as products are added,
/// preventing double-booking between NON_GST_ERP and GST_ERP.
class BillingProvider with ChangeNotifier {
  // ── State ─────────────────────────────────────────────────────────────────
  Customer             _customer      = Customer.walkIn;
  String               _customerPhone = '';
  final List<BillItem> _items         = [];
  String _paymentType = AppConstants.paymentTypes.first;
  String _salesType   = AppConstants.salesTypes.first;
  String _priceList   = AppConstants.priceLists.first;
  String _through     = '';
  String _area        = '';
  String _remarks     = '';

  /// Draft bill identifier — generated once per billing session.
  /// Sent to backend with every reservation so the DB can group them.
  /// A real bill_drafts row is created in the DB when the session starts.
  String _draftBillId = _generateDraftId();

  /// Whether the bill_drafts row has been created in the DB yet.
  bool _draftCreated = false;

  /// Maps productId → reservationId for active reservations in this draft.
  final Map<String, String> _reservationIds = {};

  // ── Getters ───────────────────────────────────────────────────────────────
  Customer         get customer      => _customer;
  String           get customerPhone => _customerPhone;
  List<BillItem>   get items         => List.unmodifiable(_items);
  String           get paymentType   => _paymentType;
  String           get salesType     => _salesType;
  String           get priceList     => _priceList;
  String           get through       => _through;
  String           get area          => _area;
  String           get remarks       => _remarks;
  int              get itemCount     => _items.length;
  String           get draftBillId   => _draftBillId;

  // ── Computed totals (no GST) ──────────────────────────────────────────────
  double get subtotal      => _r(_items.fold(0.0, (s, i) => s + i.grossAmount));
  double get gstTotal      => 0.0;
  double get roundOff      => 0.0;
  double get grandTotal    => _r(_items.fold(0.0, (s, i) => s + i.total));

  Map<String, double> get gstBreakup => {};

  double _r(double v) => double.parse(v.toStringAsFixed(2));

  // ── Setters ───────────────────────────────────────────────────────────────
  void setCustomer(Customer c) {
    _customer      = c;
    _area          = c.area;
    _customerPhone = c.phone;
    notifyListeners();
  }
  void setCustomerPhone(String v) { _customerPhone = v; notifyListeners(); }
  void setPaymentType(String v)   { _paymentType = v; notifyListeners(); }
  void setSalesType(String v)     { _salesType   = v; notifyListeners(); }
  void setPriceList(String v)     { _priceList   = v; notifyListeners(); }
  void setThrough(String v)       { _through     = v; notifyListeners(); }
  void setArea(String v)          { _area        = v; notifyListeners(); }
  void setRemarks(String v)       { _remarks     = v; notifyListeners(); }

  // ── Item management ───────────────────────────────────────────────────────

  /// Ensures a bill_drafts row exists in the DB for this session.
  /// Called lazily before the first reservation of each session.
  Future<void> _ensureDraftCreated() async {
    if (_draftCreated) return;
    final result = await ApiService.createDraft(draftId: _draftBillId);
    if (result.success) {
      _draftCreated = true;
    }
    // If it fails (network issue), we proceed anyway — the draft ID is still
    // valid as a TEXT key in stock_reservations even without a bill_drafts row.
  }

  /// Attempts to reserve [quantity] units of [product] in the database.
  ///
  /// Returns a [ReservationResult] indicating success or the reason for failure.
  /// The product is only added to the bill if the database reservation succeeds.
  ///
  /// For an existing item in the bill (quantity increase), uses the atomic
  /// update_reservation RPC so there is no race-condition window where the
  /// freed stock could be grabbed by the GST ERP between release and re-reserve.
  Future<ReservationResult> addProductWithReservation(
    Product product, {
    double quantity = 1,
  }) async {
    // Ensure the bill_drafts row exists in the DB before first reservation
    await _ensureDraftCreated();

    final existingIdx = _items.indexWhere((i) => i.productId == product.id);

    // ── Existing item: atomically bump the reservation quantity ──────
    if (existingIdx != -1) {
      final priorReservationId = _reservationIds[product.id];
      final newTotalQty = _items[existingIdx].quantity + quantity;

      if (priorReservationId != null) {
        // Atomic delta — no race window
        final result = await ApiService.updateReservation(
          reservationId: priorReservationId,
          newQuantity:   newTotalQty,
        );

        if (!result.success) {
          final errorCode = result.data?['error_code'] as String?;
          // RPC_NOT_DEPLOYED: fall back to reserve_stock upsert
          if (errorCode == 'RPC_NOT_DEPLOYED') {
            final fallback = await ApiService.reserveStock(
              productId:   product.id,
              draftBillId: _draftBillId,
              quantity:    newTotalQty,
            );
            if (fallback.success) {
              final newResId = fallback.data?['reservation_id'] as String?;
              if (newResId != null) _reservationIds[product.id] = newResId;
              _items[existingIdx].quantity = newTotalQty;
              notifyListeners();
              return const ReservationResult(success: true, message: 'Reserved');
            }
            final avail = (fallback.data?['remaining_available'] as num?)?.toDouble() ?? 0;
            return ReservationResult(
              success: false,
              errorCode: fallback.data?['error_code'] as String?,
              message: fallback.error ?? 'Reservation failed',
              remainingAvailable: avail,
            );
          }
          final available =
              (result.data?['remaining_available'] as num?)?.toDouble() ?? 0;
          return ReservationResult(
            success:            false,
            errorCode:          errorCode,
            message:            result.error ?? 'Reservation update failed',
            remainingAvailable: available,
          );
        }

        _items[existingIdx].quantity = newTotalQty;
        notifyListeners();
        return const ReservationResult(success: true, message: 'Reserved');
      }

      // No prior reservation ID — fall through to fresh reserve below
      // (release the old one if somehow we lost track)
    }

    // ── New item: fresh reserve ──────────────────────────────────────
    final newTotalQty = existingIdx != -1
        ? _items[existingIdx].quantity + quantity
        : quantity;

    // If we somehow have a stale reservation ID for a new-item scenario, release it
    if (existingIdx == -1) {
      final stale = _reservationIds.remove(product.id);
      if (stale != null) {
        await _releaseSingleReservation(stale);
      }
    }

    // Call the database reservation RPC
    final result = await ApiService.reserveStock(
      productId:    product.id,
      draftBillId:  _draftBillId,
      quantity:     newTotalQty,
    );

    if (!result.success) {
      final available = (result.data?['remaining_available'] as num?)?.toDouble() ?? 0;
      return ReservationResult(
        success:            false,
        errorCode:          result.data?['error_code'] as String?,
        message:            result.error ?? 'Reservation failed',
        remainingAvailable: available,
      );
    }

    // Store reservation ID
    final reservationId = result.data?['reservation_id'] as String?;
    if (reservationId != null) {
      _reservationIds[product.id] = reservationId;
    }

    // Update in-memory bill
    if (existingIdx != -1) {
      _items[existingIdx].quantity = newTotalQty;
    } else {
      _items.add(BillItem.fromProduct(product, quantity: quantity));
    }

    notifyListeners();
    return const ReservationResult(success: true, message: 'Reserved');
  }

  /// Release reservation and remove item from bill.
  Future<void> removeItemWithRelease(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    _items.removeAt(index);
    notifyListeners();

    // Release reservation in background
    final reservationId = _reservationIds.remove(item.productId);
    if (reservationId != null) {
      try {
        await _releaseSingleReservation(reservationId);
      } catch (_) {}
    }
  }

  /// Update quantity — uses the atomic update_reservation RPC to adjust the
  /// existing reservation by the delta, with no race-condition window.
  /// Falls back to release+re-reserve if no existing reservation ID is known.
  Future<ReservationResult> updateQuantityWithReservation(
    int index,
    double newQuantity,
    Product product,
  ) async {
    if (index < 0 || index >= _items.length) {
      return const ReservationResult(success: false, message: 'Invalid index');
    }
    if (newQuantity <= 0) {
      await removeItemWithRelease(index);
      return const ReservationResult(success: true, message: 'Item removed');
    }

    final existingReservationId = _reservationIds[product.id];

    // ── Fast path: atomic delta update (no race window) ─────────────
    if (existingReservationId != null) {
      final result = await ApiService.updateReservation(
        reservationId: existingReservationId,
        newQuantity:   newQuantity,
      );

      if (!result.success) {
        final errorCode = result.data?['error_code'] as String?;
        // RPC_NOT_DEPLOYED: migration 0006 pending — fall back to reserve_stock
        // upsert which the live DB handles atomically for same bill+product.
        if (errorCode == 'RPC_NOT_DEPLOYED') {
          final fallback = await ApiService.reserveStock(
            productId:   product.id,
            draftBillId: _draftBillId,
            quantity:    newQuantity,
          );
          if (fallback.success) {
            final newResId = fallback.data?['reservation_id'] as String?;
            if (newResId != null) _reservationIds[product.id] = newResId;
            _items[index].quantity = newQuantity;
            notifyListeners();
            return const ReservationResult(success: true, message: 'Updated');
          }
          final avail = (fallback.data?['remaining_available'] as num?)?.toDouble() ?? 0;
          return ReservationResult(
            success: false,
            errorCode: fallback.data?['error_code'] as String?,
            message: fallback.error ?? 'Update failed',
            remainingAvailable: avail,
          );
        }
        // Leave the item at its current quantity — do not change anything
        final available =
            (result.data?['remaining_available'] as num?)?.toDouble() ?? 0;
        return ReservationResult(
          success:            false,
          errorCode:          errorCode,
          message:            result.error ?? 'Reservation update failed',
          remainingAvailable: available,
        );
      }

      _items[index].quantity = newQuantity;
      notifyListeners();
      return const ReservationResult(success: true, message: 'Updated');
    }

    // ── Slow path: no prior reservation ID — release + full re-reserve
    // (Handles edge case where provider was recreated / reservation ID lost)
    final oldReservationId = _reservationIds.remove(product.id);
    if (oldReservationId != null) {
      await _releaseSingleReservation(oldReservationId);
    }

    final result = await ApiService.reserveStock(
      productId:   product.id,
      draftBillId: _draftBillId,
      quantity:    newQuantity,
    );

    if (!result.success) {
      notifyListeners();
      final available =
          (result.data?['remaining_available'] as num?)?.toDouble() ?? 0;
      return ReservationResult(
        success:            false,
        errorCode:          result.data?['error_code'] as String?,
        message:            result.error ?? 'Reservation failed',
        remainingAvailable: available,
      );
    }

    final reservationId = result.data?['reservation_id'] as String?;
    if (reservationId != null) {
      _reservationIds[product.id] = reservationId;
    }

    _items[index].quantity = newQuantity;
    notifyListeners();
    return const ReservationResult(success: true, message: 'Updated');
  }

  // ── Legacy synchronous addProduct (kept for backward compatibility) ───────
  /// Synchronous stock check only. Prefer [addProductWithReservation] for
  /// production use. This is kept so existing code paths don't break.
  bool addProduct(Product product, {double quantity = 1}) {
    if (product.stock <= 0) return false;
    final idx = _items.indexWhere((i) => i.productId == product.id);
    if (idx != -1) {
      final current = _items[idx].quantity;
      final max     = _items[idx].maxStock;
      if (max > 0 && current >= max) return false;
      _items[idx].quantity = (current + quantity).clamp(0, max > 0 ? max : double.infinity);
    } else {
      _items.add(BillItem.fromProduct(product, quantity: quantity));
    }
    notifyListeners();
    return true;
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void updateQuantity(int index, double quantity) {
    if (index >= 0 && index < _items.length) {
      final max = _items[index].maxStock;
      _items[index].quantity = max > 0 ? quantity.clamp(1, max) : quantity;
      notifyListeners();
    }
  }

  void clearItems() { _items.clear(); notifyListeners(); }

  /// Cancel all reservations for this draft and reset the bill.
  Future<void> cancelBillWithRelease() async {
    // Release all stock reservations atomically on the backend
    if (_reservationIds.isNotEmpty) {
      try {
        await ApiService.releaseBillReservations(_draftBillId);
      } catch (_) {}
    }
    // Mark the bill_drafts row as CANCELLED
    if (_draftCreated) {
      ApiService.cancelDraft(_draftBillId);
    }
    _resetState();
  }

  void resetBill() {
    // Fire-and-forget release of any remaining reservations
    if (_reservationIds.isNotEmpty) {
      ApiService.releaseBillReservations(_draftBillId);
    }
    if (_draftCreated) {
      ApiService.cancelDraft(_draftBillId);
    }
    _resetState();
  }

  void _resetState() {
    _items.clear();
    _reservationIds.clear();
    _draftBillId   = _generateDraftId();
    _draftCreated  = false;
    _customer      = Customer.walkIn;
    _customerPhone = '';
    _paymentType   = AppConstants.paymentTypes.first;
    _salesType     = AppConstants.salesTypes.first;
    _priceList     = AppConstants.priceLists.first;
    _through       = '';
    _area          = '';
    _remarks       = '';
    notifyListeners();
  }

  bool get canSave => _items.isNotEmpty;

  // ── Internal helpers ──────────────────────────────────────────────────────

  Future<void> _releaseSingleReservation(String reservationId) async {
    await ApiService.releaseReservation(reservationId);
  }

  static String _generateDraftId() {
    final now = DateTime.now();
    return 'DRAFT-${now.millisecondsSinceEpoch}';
  }
}
