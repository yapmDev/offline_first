import '../models/product.dart';

/// Mock backend that simulates a remote server
/// In a real app, this would be actual HTTP calls
class MockBackend {
  final Map<String, Product> _products = {};
  final Set<String> _processedOperations = {};
  bool isOnline = true;

  MockBackend() {
    // Add some initial products
    _products['1'] = const Product(
      id: '1',
      name: 'Laptop',
      price: 999.99,
      stock: 10,
    );
    _products['2'] = const Product(
      id: '2',
      name: 'Mouse',
      price: 29.99,
      stock: 50,
    );
  }

  /// Get initial products (for seeding the local store)
  Map<String, Product> get initialProducts => Map.unmodifiable(_products);

  void _ensureOnline() {
    if (!isOnline) {
      throw Exception('Backend is offline');
    }
  }

  Future<void> createProduct(Product product) async {
    _ensureOnline();
    _products[product.id] = product;
  }

  Future<void> updateProduct(String id, Map<String, dynamic> updates) async {
    _ensureOnline();
    final existing = _products[id];
    if (existing == null) {
      throw Exception('Product not found: $id');
    }

    _products[id] = Product(
      id: id,
      name: updates['name'] as String? ?? existing.name,
      price: updates['price'] as double? ?? existing.price,
      stock: updates['stock'] as int? ?? existing.stock,
    );
  }

  Future<void> deleteProduct(String id) async {
    _ensureOnline();
    _products.remove(id);
  }

  Future<Product?> getProduct(String id) async {
    _ensureOnline();
    return _products[id];
  }

  Future<List<Product>> getAllProducts() async {
    _ensureOnline();
    return _products.values.toList();
  }

  bool hasProcessedOperation(String operationId) {
    return _processedOperations.contains(operationId);
  }

  void markOperationProcessed(String operationId) {
    _processedOperations.add(operationId);
  }

  void clearProcessedOperations() {
    _processedOperations.clear();
  }
}
