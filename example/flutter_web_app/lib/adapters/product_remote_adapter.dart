import 'dart:async';
import 'package:offline_first/offline_first.dart';
import '../models/product.dart';
import '../backend/mock_backend.dart';

/// Remote adapter for Product entity
/// In a real app, this would make HTTP requests
class ProductRemoteAdapter extends RemoteAdapter<Product> {
  final MockBackend backend;

  ProductRemoteAdapter(this.backend);

  @override
  String get entityType => 'product';

  @override
  Future<SyncResult> create(Operation operation) async {
    try {
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));

      // Check idempotency
      if (backend.hasProcessedOperation(operation.operationId)) {
        // Already processed, return success
        return SyncResult.success();
      }

      // Send to backend
      final product = ProductOfflineExtension.fromMap(operation.payload);
      await backend.createProduct(product);

      // Mark operation as processed
      backend.markOperationProcessed(operation.operationId);

      return SyncResult.success();
    } catch (e) {
      return SyncResult.failure(errorMessage: e.toString());
    }
  }

  @override
  Future<SyncResult> update(Operation operation) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      // Check idempotency
      if (backend.hasProcessedOperation(operation.operationId)) {
        return SyncResult.success();
      }

      // Send to backend
      await backend.updateProduct(operation.entityId, operation.payload);
      backend.markOperationProcessed(operation.operationId);

      return SyncResult.success();
    } catch (e) {
      return SyncResult.failure(errorMessage: e.toString());
    }
  }

  @override
  Future<SyncResult> delete(Operation operation) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      // Check idempotency
      if (backend.hasProcessedOperation(operation.operationId)) {
        return SyncResult.success();
      }

      // Send to backend
      await backend.deleteProduct(operation.entityId);
      backend.markOperationProcessed(operation.operationId);

      return SyncResult.success();
    } catch (e) {
      return SyncResult.failure(errorMessage: e.toString());
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async {
    final product = await backend.getProduct(entityId);
    return product?.toMap();
  }
}
