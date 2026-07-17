class Product {
  static const String entityType = 'product';

  final String id;
  final String name;
  final double price;
  final int stock;
  final DateTime? lastModified;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'stock': stock,
    };
  }

  static Product fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      price: map['price'] as double,
      stock: map['stock'] as int,
    );
  }

  Product copyWith({
    String? id,
    String? name,
    double? price,
    int? stock,
    DateTime? lastModified,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  @override
  String toString() {
    return 'Product(id: $id, name: $name, price: \$$price, stock: $stock)';
  }
}
