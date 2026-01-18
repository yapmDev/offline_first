import 'operation.dart';
import '../storage/storage_adapter.dart';

/// Manages the operation log with append-first semantics
class OperationLog {
  final StorageAdapter _storage;

  OperationLog(this._storage);

  /// Add a new operation to the log
  Future<void> append(Operation operation) async {
    await _storage.addOperation(operation);
  }

  /// Get all pending operations (ordered by timestamp)
  Future<List<Operation>> getPendingOperations() async {
    return _storage.getPendingOperations();
  }

  /// Get operations for a specific entity
  Future<List<Operation>> getOperationsForEntity(
    String entityType,
    String entityId,
  ) async {
    return _storage.getOperationsForEntity(entityType, entityId);
  }

  /// Update an operation (e.g., change status)
  Future<void> update(Operation operation) async {
    await _storage.updateOperation(operation);
  }

  /// Remove an operation from the log
  Future<void> remove(String operationId) async {
    await _storage.deleteOperation(operationId);
  }

  /// Remove multiple operations
  Future<void> removeMany(List<String> operationIds) async {
    await _storage.deleteOperations(operationIds);
  }

  /// Get a specific operation by ID
  Future<Operation?> getOperation(String operationId) async {
    return _storage.getOperation(operationId);
  }

  /// Get count of pending operations
  Future<int> getPendingCount() async {
    return _storage.getPendingOperationsCount();
  }

  /// Replace multiple operations with a single squashed operation
  /// Used by the operation reducer
  Future<void> squash(List<Operation> toRemove, Operation squashed) async {
    await _storage.executeTransaction((adapter) async {
      await adapter.deleteOperations(toRemove.map((op) => op.operationId).toList());
      await adapter.addOperation(squashed);
    });
  }
}
