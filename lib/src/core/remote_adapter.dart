import 'operation.dart';
import 'sync_result.dart';

/// Abstract remote adapter that translates operations into backend calls
/// This decouples the sync engine from the transport layer (REST, GraphQL, gRPC, etc.)
abstract class RemoteAdapter<T> {
  /// The entity type this adapter handles
  String get entityType;

  /// Send a create operation to the backend
  /// The adapter should ensure idempotency using the operationId
  Future<SyncResult> create(Operation operation);

  /// Send an update operation to the backend
  /// The adapter should ensure idempotency using the operationId
  Future<SyncResult> update(Operation operation);

  /// Send a delete operation to the backend
  /// The adapter should ensure idempotency using the operationId
  Future<SyncResult> delete(Operation operation);

  /// Send a custom operation to the backend
  /// The adapter should ensure idempotency using the operationId
  Future<SyncResult> custom(Operation operation) {
    throw UnimplementedError(
      'Custom operation "${operation.customOperationName}" not implemented for $entityType',
    );
  }

  /// Fetch the latest state from the server for an entity
  /// Used for conflict resolution
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId);

  /// Optional: Batch sync multiple operations
  /// Default implementation syncs one by one
  Future<List<SyncResult>> syncBatch(List<Operation> operations) async {
    final results = <SyncResult>[];
    for (final operation in operations) {
      final result = await syncOperation(operation);
      results.add(result);
    }
    return results;
  }

  /// Route operation to the appropriate method
  Future<SyncResult> syncOperation(Operation operation) {
    switch (operation.operationType) {
      case OperationType.create:
        return create(operation);
      case OperationType.update:
        return update(operation);
      case OperationType.delete:
        return delete(operation);
      case OperationType.custom:
        return custom(operation);
    }
  }
}
