/// Product model — no GST, plain sale price.
class Product {
  final String id;
  final String name;
  final String unit;
  final double price;   // final sale price (no tax)
  final double mrp;
  final double stock;
  final double availableStock;
  final String category;
  final String description;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.price,
    required this.mrp,
    required this.stock,
    double? availableStock,
    required this.category,
    this.description = '',
    this.imageUrl,
  }) : availableStock = availableStock ?? stock;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id:          json['id'].toString(),
      name:        json['name'] as String,
      unit:        json['unit'] as String,
      price:       (json['price'] as num).toDouble(),
      mrp:         (json['mrp'] as num).toDouble(),
      stock:       (json['stock'] as num).toDouble(),
      availableStock: (json['available_stock'] as num?)?.toDouble() ?? (json['stock'] as num).toDouble(),
      category:    json['category'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl:    json['image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unit': unit,
        'price': price,
        'mrp': mrp,
        'stock': stock,
        'available_stock': availableStock,
        'category': category,
        'description': description,
        'image_url': imageUrl,
      };

  // ── Computed (GST not applicable — kept for UI compatibility) ────────────
  double get gst         => 0.0;           // no GST in this system
  double get priceWithGst => price;        // price is already the final price

  /// The backend stores the SKU inside [description] as "SKU | Brand".
  String get sku => description.split(' | ').first.trim();

  @override
  String toString() => 'Product($id, $name)';
}
