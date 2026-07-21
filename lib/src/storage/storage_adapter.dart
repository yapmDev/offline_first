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

  /// Get all operations eligible for a sync attempt (ordered by timestamp).
  ///
  /// Eligible means [OperationStatus.pending], [OperationStatus.syncing] or
  /// [OperationStatus.failed]:
  /// - `syncing` is only ever observed here when a previous run died
  ///   mid-flight (the sync engine is single-flight and snapshots this list
  ///   once at the start), so including it revives orphaned operations.
  /// - `failed` exhausted its retries for a *retryable* reason, so a later
  ///   sync is worth attempting.
  ///
  /// Must exclude [OperationStatus.synced] and
  /// [OperationStatus.failedPermanent] — the latter never retries on its own.
  Future<List<Operation>> getPendingOperations();

  /// Get all operations for a specific entity
  Future<List<Operation>> getOperationsForEntity(String entityType, String entityId);

  /// Get every operation still in the log for [entityType], whatever its
  /// status. Used to tell which entities have local writes the server has not
  /// acknowledged yet, so a remote refresh does not overwrite them.
  Future<List<Operation>> getOperationsForType(String entityType);

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
