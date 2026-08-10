import 'bill_item.dart';

/// Saved bill returned from the Flask API.
class Bill {
  final String billNumber;
  final String date;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final String paymentType;
  final String salesType;
  final String through;
  final String area;
  final String priceList;
  final String remarks;
  final List<BillItem> items;
  final double subtotal;
  final double gstTotal;
  final double roundOff;
  final double grandTotal;
  final Map<String, double> gstBreakup;
  final int itemCount;

  const Bill({
    required this.billNumber,
    required this.date,
    required this.customerId,
    required this.customerName,
    this.customerPhone = '',
    required this.paymentType,
    this.salesType = 'Retail',
    this.through = '',
    this.area = '',
    this.priceList = 'Retail',
    this.remarks = '',
    required this.items,
    required this.subtotal,
    required this.gstTotal,
    required this.roundOff,
    required this.grandTotal,
    required this.gstBreakup,
    required this.itemCount,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    final rawBreakup = (json['gst_breakup'] as Map<String, dynamic>?) ?? {};
    final gstBreakup = rawBreakup.map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );

    return Bill(
      billNumber:    json['bill_number']   as String,
      date:          json['date']          as String,
      customerId:    json['customer_id']   as int,
      customerName:  json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String? ?? '',
      paymentType:   json['payment_type']  as String? ?? 'Cash',
      salesType:     json['sales_type']    as String? ?? 'Retail',
      through:       json['through']       as String? ?? '',
      area:          json['area']          as String? ?? '',
      priceList:     json['price_list']    as String? ?? 'Retail',
      remarks:       json['remarks']       as String? ?? '',
      items: (json['items'] as List<dynamic>)
          .map((e) => BillItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtotal:      (json['subtotal']      as num?)?.toDouble() ?? 0.0,
      gstTotal:      (json['gst_total']     as num?)?.toDouble() ?? 0.0,
      roundOff:      (json['round_off']     as num?)?.toDouble() ?? 0.0,
      grandTotal:    (json['grand_total']   as num).toDouble(),
      gstBreakup:    gstBreakup,
      itemCount:     json['item_count']    as int? ??
                     (json['items'] as List<dynamic>?)?.length ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'bill_number': billNumber,
        'date': date,
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'payment_type': paymentType,
        'sales_type': salesType,
        'through': through,
        'area': area,
        'price_list': priceList,
        'remarks': remarks,
        'items': items.map((e) => e.toJson()).toList(),
        'subtotal': subtotal,
        'gst_total': gstTotal,
        'round_off': roundOff,
        'grand_total': grandTotal,
        'gst_breakup': gstBreakup,
        'item_count': itemCount,
      };
}
