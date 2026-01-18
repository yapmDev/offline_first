import 'dart:async';
import 'package:uuid/uuid.dart';

import 'operation.dart';
import 'operation_log.dart';
import 'remote_adapter.dart';
import '../storage/storage_adapter.dart';
import '../sync/sync_engine.dart';
import '../sync/operation_reducer.dart';
import '../conflict/conflict_resolver.dart';

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

  // ========== CRUD Operations ==========

  /// Save an entity (create or update)
  /// This creates an operation and applies it locally immediately
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

  /// Get an entity by ID
  Future<Map<String, dynamic>?> get(String entityType, String entityId) async {
    _ensureInitialized();
    return _storage.getEntity(entityType, entityId);
  }

  /// Get all entities of a type
  Future<List<Map<String, dynamic>>> getAll(String entityType) async {
    _ensureInitialized();
    return _storage.getAllEntities(entityType);
  }

  /// Execute a custom operation
  Future<void> executeCustomOperation(
    String entityType,
    String entityId,
    String operationName,
    Map<String, dynamic> payload,
  ) async {
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
    );

    // Note: custom operations may or may not modify local state
    // This depends on the business logic

    // Add to operation log
    await _operationLog.append(operation);
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
