import '../core/operation.dart';

/// Abstract storage adapter to decouple from specific storage implementations
/// This allows the package to work with any storage backend (Hive, SQLite, SharedPreferences, etc.)
abstract class StorageAdapter {
  /// Initialize the storage
  Future<void> initialize();

  /// Close/dispose the storage
  Future<void> close();

  // ============ Entity Operations ============

  /// Save an entity
  Future<void> saveEntity(String entityType, String entityId, Map<String, dynamic> data);

  /// Get an entity by ID
  Future<Map<String, dynamic>?> getEntity(String entityType, String entityId);

  /// Get all entities of a type
  Future<List<Map<String, dynamic>>> getAllEntities(String entityType);

  /// Delete an entity
  Future<void> deleteEntity(String entityType, String entityId);

  /// Check if an entity exists
  Future<bool> entityExists(String entityType, String entityId);

  // ============ Operation Log Operations ============

  /// Add an operation to the log
  Future<void> addOperation(Operation operation);

  /// Get an operation by ID
  Future<Operation?> getOperation(String operationId);

  /// Get all pending operations (ordered by timestamp)
  Future<List<Operation>> getPendingOperations();

  /// Get all operations for a specific entity
  Future<List<Operation>> getOperationsForEntity(String entityType, String entityId);

  /// Update an operation's status
  Future<void> updateOperation(Operation operation);

  /// Delete an operation
  Future<void> deleteOperation(String operationId);

  /// Delete multiple operations
  Future<void> deleteOperations(List<String> operationIds);

  /// Get count of pending operations
  Future<int> getPendingOperationsCount();

  // ============ Metadata Operations ============

  /// Save metadata (deviceId, lastSyncTime, etc.)
  Future<void> saveMetadata(String key, dynamic value);

  /// Get metadata
  Future<dynamic> getMetadata(String key);

  /// Clear all metadata
  Future<void> clearMetadata();

  // ============ Batch Operations ============

  /// Execute multiple operations in a transaction
  /// Returns true if transaction succeeded
  Future<bool> executeTransaction(Future<void> Function(StorageAdapter adapter) operations);

  /// Clear all data (for testing purposes)
  Future<void> clearAll();
}
