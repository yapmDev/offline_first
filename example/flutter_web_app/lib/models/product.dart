import 'package:offline_first/offline_first.dart';

part 'product.offline.g.dart';

@OfflineEntity(
  type: 'product',
  idField: 'id',
)
class Product {
  final String id;
  final String name;
  final double price;
  final int stock;

  @OfflineIgnore()
  final DateTime? lastModified;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    this.lastModified,
  });

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
