import 'dart:async';
import 'package:uuid/uuid.dart';

import 'operation.dart';
import 'operation_log.dart';
import 'remote_adapter.dart';
import '../storage/storage_adapter.dart';
import '../sync/sync_engine.dart';
import '../sync/operation_reducer.dart';
import '../conflict/conflict_resolver.dart';
import '../conflict/sync_conflict.dart';

/// Configuration for the OfflineStore
class OfflineStoreConfig {
  /// Device identifier for tracking operations
  final String deviceId;

  /// Sync configuration
  final SyncConfig syncConfig;

  /// Whether to auto-generate entity IDs if not provided
  final bool autoGenerateIds;

  const OfflineStoreConfig({
    required this.deviceId,
    this.syncConfig = const SyncConfig(),
    this.autoGenerateIds = true,
  });
}

/// Main API for offline-first operations
/// This is the primary interface that users interact with
class OfflineStore {
  final StorageAdapter _storage;
  final OperationLog _operationLog;
  final SyncEngine _syncEngine;
  final OfflineStoreConfig _config;
  final Map<String, RemoteAdapter<dynamic>> _adapters = {};
  final _uuid = const Uuid();

  bool _initialized = false;

  OfflineStore._({
    required StorageAdapter storage,
    required OperationLog operationLog,
    required SyncEngine syncEngine,
    required OfflineStoreConfig config,
  })  : _storage = storage,
        _operationLog = operationLog,
        _syncEngine = syncEngine,
        _config = config;

  /// Initialize the offline store
  static Future<OfflineStore> init({
    required StorageAdapter storage,
    required Map<String, RemoteAdapter<dynamic>> adapters,
    ConflictResolver? conflictResolver,
    OperationReducer? operationReducer,
    OfflineStoreConfig? config,
  }) async {
    await storage.initialize();

    final operationLog = OperationLog(storage);

    final syncEngine = SyncEngine(
      operationLog: operationLog,
      storage: storage,
      adapters: adapters,
      conflictResolver: conflictResolver,
      operationReducer: operationReducer,
      config: config?.syncConfig,
    );

    final store = OfflineStore._(
      storage: storage,
      operationLog: operationLog,
      syncEngine: syncEngine,
      config: config ?? OfflineStoreConfig(deviceId: const Uuid().v4()),
    );

    store._adapters.addAll(adapters);
    store._initialized = true;

    return store;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('OfflineStore not initialized. Call OfflineStore.init() first.');
    }
  }

  // ========== Operation Logging (Recommended) ==========

  /// Log a CREATE operation without modifying local storage
  /// The app is responsible for saving the entity to its own storage
  Future<void> logCreate(
    String entityType,
    String entityId,
    Map<String, dynamic> payload,
  ) async {
    _ensureInitialized();

    final operation = Operation(
      operationId: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operationType: OperationType.create,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: OperationStatus.pending,
      deviceId: _config.deviceId,
    );

    await _operationLog.append(operation);
  }

  /// Log an UPDATE operation without modifying local storage
  /// The app is responsible for updating the entity in its own storage
  ///
  /// [baseVersion] is the entity version this edit was made on top of. Pass it
  /// and the backend can refuse a write built on stale data, which is what
  /// surfaces a conflict instead of silently overwriting someone else. Omit it
  /// and the write keeps whatever last-write-wins behaviour the backend had.
  Future<void> logUpdate(
    String entityType,
    String entityId,
    Map<String, dynamic> payload, {
    int? baseVersion,
  }) async {
    _ensureInitialized();

    final operation = Operation(
      operationId: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operationType: OperationType.update,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: OperationStatus.pending,
      deviceId: _config.deviceId,
      baseVersion: baseVersion,
    );

    await _operationLog.append(operation);
  }

  /// Log a DELETE operation without modifying local storage
  /// The app is responsible for deleting the entity from its own storage
  Future<void> logDelete(
    String entityType,
    String entityId, {
    int? baseVersion,
  }) async {
    _ensureInitialized();

    final operation = Operation(
      operationId: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operationType: OperationType.delete,
      payload: {},
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: OperationStatus.pending,
      deviceId: _config.deviceId,
      baseVersion: baseVersion,
    );

    await _operationLog.append(operation);
  }

  /// Log a CUSTOM operation without modifying local storage
  ///
  /// Custom operations are usually deltas ("add 5", "record a payment"), which
  /// stay correct whatever the entity version is — leave [baseVersion] unset
  /// for those, or the backend will reject writes that were perfectly valid.
  Future<void> logCustom(
    String entityType,
    String entityId,
    String operationName,
    Map<String, dynamic> payload, {
    int? baseVersion,
  }) async {
    _ensureInitialized();

    final operation = Operation(
      operationId: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operationType: OperationType.custom,
      customOperationName: operationName,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: OperationStatus.pending,
      deviceId: _config.deviceId,
      baseVersion: baseVersion,
    );

    await _operationLog.append(operation);
  }

  // ========== CRUD Operations (Legacy - manages both storage and logging) ==========

  /// Save an entity (create or update)
  /// This creates an operation and applies it locally immediately
  ///
  /// NOTE: For apps with existing storage, prefer using logCreate/logUpdate
  /// and managing your own storage separately
  Future<void> save(
    String entityType,
    String entityId,
    Map<String, dynamic> data, {
    bool isNew = false,
  }) async {
    _ensureInitialized();

    // Check if entity exists
    final exists = await _storage.entityExists(entityType, entityId);

    // Determine operation type
    final operationType = isNew || !exists ? OperationType.create : OperationType.update;

    // Create operation
    final operation = Operation(
      operationId: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      payload: data,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: OperationStatus.pending,
      deviceId: _config.deviceId,
    );

    // Apply locally first (source of truth)
    await _storage.saveEntity(entityType, entityId, data);

    // Add to operation log
    await _operationLog.append(operation);
  }

  /// Delete an entity
  ///
  /// NOTE: For apps with existing storage, prefer using logDelete
  /// and managing your own storage separately
  Future<void> delete(String entityType, String entityId) async {
    _ensureInitialized();

    // Create delete operation
    final operation = Operation(
      operationId: _uuid.v4(),
      entityType: entityType,
      entityId: entityId,
      operationType: OperationType.delete,
      payload: {},
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: OperationStatus.pending,
      deviceId: _config.deviceId,
    );

    // Apply locally first
    await _storage.deleteEntity(entityType, entityId);

    // Add to operation log
    await _operationLog.append(operation);
  }

  // ========== Storage Operations (Legacy - for apps using OfflineStore as source of truth) ==========

  /// Get an entity by ID from storage
  ///
  /// NOTE: For apps with existing storage, read from your own storage instead
  Future<Map<String, dynamic>?> get(String entityType, String entityId) async {
    _ensureInitialized();
    return _storage.getEntity(entityType, entityId);
  }

  /// Get all entities of a type from storage
  ///
  /// NOTE: For apps with existing storage, read from your own storage instead
  Future<List<Map<String, dynamic>>> getAll(String entityType) async {
    _ensureInitialized();
    return _storage.getAllEntities(entityType);
  }

  /// Execute a custom operation
  ///
  /// NOTE: For apps with existing storage, prefer using logCustom
  @Deprecated('Use logCustom instead for apps with existing storage')
  Future<void> executeCustomOperation(
    String entityType,
    String entityId,
    String operationName,
    Map<String, dynamic> payload,
  ) async {
    await logCustom(entityType, entityId, operationName, payload);
  }

  // ========== Sync Operations ==========

  /// Start syncing pending operations
  Future<void> sync() async {
    _ensureInitialized();
    await _syncEngine.sync();
  }

  /// Stream of sync status updates
  Stream<SyncStatusEvent> get syncStatusStream => _syncEngine.statusStream;

  /// Get current sync status
  SyncStatus get syncStatus => _syncEngine.status;

  /// Whether sync is currently in progress
  bool get isSyncing => _syncEngine.isSyncing;

  /// Get count of pending operations
  Future<int> getPendingOperationsCount() async {
    _ensureInitialized();
    return _operationLog.getPendingCount();
  }

  /// Get all pending operations (for debugging/UI)
  Future<List<Operation>> getPendingOperations() async {
    _ensureInitialized();
    return _operationLog.getPendingOperations();
  }

  /// Ids of [entityType] entities that still carry an unsynced local write,
  /// whatever the operation's status.
  ///
  /// A remote refresh must not overwrite nor prune these: the server does not
  /// know about them yet, so its version is stale by definition. Dropping the
  /// guard loses the local edit (overwrite) or the whole record (prune of an
  /// id the server has never seen).
  Future<Set<String>> unsyncedEntityIds(String entityType) async {
    _ensureInitialized();
    final operations = await _operationLog.getOperationsForType(entityType);
    return operations.map((op) => op.entityId).toSet();
  }

  // ========== Conflicts ==========

  /// Conflicts raised as they are detected.
  ///
  /// Live only — call [getConflicts] on startup for the ones already parked.
  Stream<SyncConflict> get conflictStream => _syncEngine.conflictStream;

  /// Every conflict waiting on a decision.
  Future<List<SyncConflict>> getConflicts() async {
    _ensureInitialized();
    final operations =
        await _operationLog.getOperationsByStatus(OperationStatus.conflicted);
    return operations.map(SyncConflict.new).toList();
  }

  /// Whether anything is waiting on a decision.
  Future<int> getConflictCount() async {
    _ensureInitialized();
    final operations =
        await _operationLog.getOperationsByStatus(OperationStatus.conflicted);
    return operations.length;
  }

  /// Settle a parked conflict.
  ///
  /// [ConflictChoice.keepLocal] re-queues the write rebased onto the server's
  /// version, optionally with a [payload] that replaces the original — that is
  /// how a merge is applied, since only the caller knows the shape its backend
  /// expects. Rebasing is what stops the retry from conflicting again.
  ///
  /// [ConflictChoice.keepRemote] adopts the server's state locally and drops
  /// the write. [ConflictChoice.discard] drops the write and leaves local
  /// state alone, for when the decision moves elsewhere.
  ///
  /// Throws [StateError] if the operation is gone or is not conflicted —
  /// two devices resolving the same conflict should not both apply.
  Future<void> resolveConflict(
    String operationId,
    ConflictChoice choice, {
    Map<String, dynamic>? payload,
  }) async {
    _ensureInitialized();

    final operation = await _operationLog.getOperation(operationId);
    if (operation == null) {
      throw StateError('Operation $operationId is no longer in the log');
    }
    if (!operation.isConflicted) {
      throw StateError(
        'Operation $operationId is ${operation.status.name}, not conflicted',
      );
    }

    switch (choice) {
      case ConflictChoice.keepLocal:
        await _operationLog.update(
          operation.rebased(
            baseVersion: operation.conflictServerVersion,
            payload: payload,
          ),
        );

      case ConflictChoice.keepRemote:
        final serverState = operation.conflictData;
        if (serverState != null) {
          await _storage.saveEntity(
            operation.entityType,
            operation.entityId,
            serverState,
          );
        }
        await _operationLog.remove(operationId);

      case ConflictChoice.discard:
        await _operationLog.remove(operationId);
    }
  }

  /// Drop an operation from the queue whatever its status.
  ///
  /// For giving up on a write that cannot be sent — a permanent failure that
  /// no edit will fix. Local state is left untouched.
  Future<void> discardOperation(String operationId) async {
    _ensureInitialized();
    await _operationLog.remove(operationId);
  }

  /// Put a parked operation back in the queue.
  ///
  /// Useful for a permanent failure whose cause was fixed elsewhere (a
  /// duplicate name freed up, a permission granted). A conflicted operation
  /// should go through [resolveConflict] instead, so it gets rebased.
  Future<void> retryOperation(String operationId) async {
    _ensureInitialized();
    final operation = await _operationLog.getOperation(operationId);
    if (operation == null) {
      throw StateError('Operation $operationId is no longer in the log');
    }
    await _operationLog.update(
      operation.copyWith(status: OperationStatus.pending, retryCount: 0),
    );
  }

  /// Operations that will not be retried on their own.
  Future<List<Operation>> getFailedOperations() async {
    _ensureInitialized();
    return _operationLog.getOperationsByStatus(OperationStatus.failedPermanent);
  }

  // ========== Lifecycle ==========

  /// Close the store and cleanup resources
  Future<void> close() async {
    _syncEngine.dispose();
    await _storage.close();
    _initialized = false;
  }

  /// Clear all data (use with caution)
  Future<void> clearAll() async {
    _ensureInitialized();
    await _storage.clearAll();
  }
}
