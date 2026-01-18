import 'dart:async';
import '../core/operation.dart';
import '../core/operation_log.dart';
import '../core/remote_adapter.dart';
import '../core/sync_result.dart';
import '../storage/storage_adapter.dart';
import '../conflict/conflict_resolver.dart';
import '../core/conflict_resolution.dart';
import 'operation_reducer.dart';

/// Represents the current sync status
enum SyncStatus {
  idle,
  syncing,
  error,
}

/// Sync status event
class SyncStatusEvent {
  final SyncStatus status;
  final int totalOperations;
  final int completedOperations;
  final String? errorMessage;

  const SyncStatusEvent({
    required this.status,
    this.totalOperations = 0,
    this.completedOperations = 0,
    this.errorMessage,
  });

  double get progress {
    if (totalOperations == 0) return 0.0;
    return completedOperations / totalOperations;
  }
}

/// Configuration for sync behavior
class SyncConfig {
  /// Maximum retry attempts for failed operations
  final int maxRetries;

  /// Whether to reduce operations before syncing
  final bool enableOperationReduction;

  /// Whether to stop sync on first error
  final bool stopOnError;

  const SyncConfig({
    this.maxRetries = 3,
    this.enableOperationReduction = true,
    this.stopOnError = false,
  });
}

/// The sync engine orchestrates syncing operations with the remote backend
class SyncEngine {
  final OperationLog _operationLog;
  final StorageAdapter _storage;
  final Map<String, RemoteAdapter<dynamic>> _adapters;
  final ConflictResolver? _conflictResolver;
  final OperationReducer _operationReducer;
  final SyncConfig _config;

  final _statusController = StreamController<SyncStatusEvent>.broadcast();
  SyncStatus _currentStatus = SyncStatus.idle;
  bool _isSyncing = false;

  SyncEngine({
    required OperationLog operationLog,
    required StorageAdapter storage,
    required Map<String, RemoteAdapter<dynamic>> adapters,
    ConflictResolver? conflictResolver,
    OperationReducer? operationReducer,
    SyncConfig? config,
  })  : _operationLog = operationLog,
        _storage = storage,
        _adapters = adapters,
        _conflictResolver = conflictResolver,
        _operationReducer = operationReducer ?? DefaultOperationReducer(),
        _config = config ?? const SyncConfig();

  /// Stream of sync status events
  Stream<SyncStatusEvent> get statusStream => _statusController.stream;

  /// Current sync status
  SyncStatus get status => _currentStatus;

  /// Whether sync is currently in progress
  bool get isSyncing => _isSyncing;

  /// Start syncing pending operations
  Future<void> sync() async {
    if (_isSyncing) {
      throw StateError('Sync already in progress');
    }

    _isSyncing = true;
    _updateStatus(SyncStatus.syncing);

    try {
      // Get all pending operations
      var pendingOps = await _operationLog.getPendingOperations();

      if (pendingOps.isEmpty) {
        _updateStatus(SyncStatus.idle);
        _isSyncing = false;
        return;
      }

      // Optionally reduce operations
      if (_config.enableOperationReduction) {
        pendingOps = await _reduceOperations(pendingOps);
      }

      _emitProgress(pendingOps.length, 0);

      // Sync operations in order
      int completed = 0;
      for (final operation in pendingOps) {
        final success = await _syncOperation(operation);

        if (!success && _config.stopOnError) {
          _updateStatus(
            SyncStatus.error,
            errorMessage: 'Sync stopped due to error',
          );
          _isSyncing = false;
          return;
        }

        completed++;
        _emitProgress(pendingOps.length, completed);
      }

      // Save last sync time
      await _storage.saveMetadata('lastSyncTime', DateTime.now().millisecondsSinceEpoch);

      _updateStatus(SyncStatus.idle);
    } catch (e) {
      _updateStatus(SyncStatus.error, errorMessage: e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  /// Reduce operations before syncing
  Future<List<Operation>> _reduceOperations(List<Operation> operations) async {
    // Group by entity
    final byEntity = <String, List<Operation>>{};
    for (final op in operations) {
      final key = '${op.entityType}:${op.entityId}';
      byEntity.putIfAbsent(key, () => []).add(op);
    }

    final reduced = <Operation>[];
    for (final entry in byEntity.entries) {
      final entityOps = entry.value;
      final reducedOps = _operationReducer.reduceMany(entityOps);

      if (reducedOps.isNotEmpty) {
        // Replace original operations with reduced ones
        await _operationLog.squash(entityOps, reducedOps.first);

        // If multiple reduced ops remain, add them back
        if (reducedOps.length > 1) {
          for (int i = 1; i < reducedOps.length; i++) {
            await _operationLog.append(reducedOps[i]);
          }
        }

        reduced.addAll(reducedOps);
      } else {
        // Operations cancelled out
        await _operationLog.removeMany(
          entityOps.map((op) => op.operationId).toList(),
        );
      }
    }

    // Sort by timestamp
    reduced.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return reduced;
  }

  /// Sync a single operation
  Future<bool> _syncOperation(Operation operation) async {
    final adapter = _adapters[operation.entityType];
    if (adapter == null) {
      // No adapter registered, mark as failed
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failed,
          errorMessage: 'No adapter registered for ${operation.entityType}',
        ),
      );
      return false;
    }

    // Mark as syncing
    await _operationLog.update(
      operation.copyWith(status: OperationStatus.syncing),
    );

    try {
      // Send to remote
      final result = await adapter.syncOperation(operation);

      if (result.success) {
        // Success - mark as synced and remove from log
        await _operationLog.remove(operation.operationId);

        // Update entity with server response if provided
        if (result.resolvedPayload != null) {
          await _storage.saveEntity(
            operation.entityType,
            operation.entityId,
            result.resolvedPayload!,
          );
        }

        return true;
      } else if (result.conflictData != null) {
        // Conflict detected
        return await _handleConflict(operation, result, adapter);
      } else {
        // Failure - handle retry logic
        return await _handleFailure(operation, result);
      }
    } catch (e) {
      // Exception during sync
      return await _handleException(operation, e);
    }
  }

  /// Handle conflict resolution
  Future<bool> _handleConflict(
    Operation operation,
    SyncResult result,
    RemoteAdapter<dynamic> adapter,
  ) async {
    if (_conflictResolver == null) {
      // No resolver configured, mark as failed
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failed,
          errorMessage: 'Conflict detected but no resolver configured',
        ),
      );
      return false;
    }

    try {
      // Get local state
      final localData = await _storage.getEntity(
        operation.entityType,
        operation.entityId,
      );
      if (localData == null) {
        // Entity doesn't exist locally anymore
        await _operationLog.remove(operation.operationId);
        return true;
      }

      final localState = LocalState(
        data: localData,
        timestamp: operation.timestamp,
      );

      final remoteState = RemoteState(
        data: result.conflictData!,
        timestamp: result.serverTimestamp ?? DateTime.now().millisecondsSinceEpoch,
      );

      // Get all pending operations for this entity
      final pendingOps = await _operationLog.getOperationsForEntity(
        operation.entityType,
        operation.entityId,
      );

      // Resolve conflict
      final resolution = await _conflictResolver!.resolve(
        localState,
        remoteState,
        pendingOps,
      );

      // Apply resolution
      return await _applyResolution(operation, resolution, remoteState);
    } catch (e) {
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failed,
          errorMessage: 'Conflict resolution failed: $e',
        ),
      );
      return false;
    }
  }

  /// Apply conflict resolution
  Future<bool> _applyResolution(
    Operation operation,
    Resolution resolution,
    RemoteState remote,
  ) async {
    switch (resolution.strategy) {
      case ResolutionStrategy.useLocal:
        // Retry the operation
        await _operationLog.update(
          operation.copyWith(
            status: OperationStatus.pending,
            retryCount: operation.retryCount + 1,
          ),
        );
        return true;

      case ResolutionStrategy.useRemote:
        // Accept remote version
        await _storage.saveEntity(
          operation.entityType,
          operation.entityId,
          remote.data,
        );
        await _operationLog.remove(operation.operationId);
        return true;

      case ResolutionStrategy.merge:
        // Apply merged data
        if (resolution.mergedData != null) {
          await _storage.saveEntity(
            operation.entityType,
            operation.entityId,
            resolution.mergedData!,
          );
          // Create new operation with merged data
          final mergedOp = operation.copyWith(
            payload: resolution.mergedData,
            status: OperationStatus.pending,
          );
          await _operationLog.update(mergedOp);
          return true;
        }
        return false;

      case ResolutionStrategy.manual:
        // Mark for manual intervention
        await _operationLog.update(
          operation.copyWith(
            status: OperationStatus.failed,
            errorMessage: 'Manual conflict resolution required',
          ),
        );
        return false;
    }
  }

  /// Handle sync failure
  Future<bool> _handleFailure(Operation operation, SyncResult result) async {
    if (!result.isRetryable || operation.retryCount >= _config.maxRetries) {
      // Max retries reached or not retryable
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failed,
          errorMessage: result.errorMessage,
        ),
      );
      return false;
    } else {
      // Retry later
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.pending,
          retryCount: operation.retryCount + 1,
          errorMessage: result.errorMessage,
        ),
      );
      return true;
    }
  }

  /// Handle exception during sync
  Future<bool> _handleException(Operation operation, Object error) async {
    if (operation.retryCount >= _config.maxRetries) {
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failed,
          errorMessage: error.toString(),
        ),
      );
      return false;
    } else {
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.pending,
          retryCount: operation.retryCount + 1,
          errorMessage: error.toString(),
        ),
      );
      return true;
    }
  }

  void _updateStatus(SyncStatus status, {String? errorMessage}) {
    _currentStatus = status;
    _statusController.add(
      SyncStatusEvent(
        status: status,
        errorMessage: errorMessage,
      ),
    );
  }

  void _emitProgress(int total, int completed) {
    _statusController.add(
      SyncStatusEvent(
        status: SyncStatus.syncing,
        totalOperations: total,
        completedOperations: completed,
      ),
    );
  }

  void dispose() {
    _statusController.close();
  }
}
