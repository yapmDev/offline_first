import 'dart:async';
import '../core/operation.dart';
import '../core/operation_log.dart';
import '../core/remote_adapter.dart';
import '../core/sync_result.dart';
import '../storage/storage_adapter.dart';
import '../conflict/conflict_resolver.dart';
import '../conflict/sync_conflict.dart';
import '../core/conflict_resolution.dart';
import 'operation_reducer.dart';

/// What syncing one operation left behind.
enum _SyncOutcome {
  /// Applied on the server; the operation is gone from the log.
  synced,

  /// Still queued — a later sync will try again on its own.
  retryable,

  /// Parked: conflicted, or rejected in a way retrying cannot fix. Later
  /// operations on the same entity are held back for this pass, since they
  /// were built on the same assumption this one just disproved.
  stalled,
}

/// Represents the current sync status
enum SyncStatus {
  idle,
  syncing,
  error,
}

/// Represents the current phase during sync
enum SyncPhase {
  /// Initial state, not syncing
  idle,

  /// Preparing: fetching pending operations
  preparing,

  /// Reducing: squashing/optimizing operations
  reducing,

  /// Syncing: sending operations to remote
  syncing,

  /// Completed successfully
  completed,
}

/// Sync status event
class SyncStatusEvent {
  final SyncStatus status;
  final SyncPhase phase;
  final int totalOperations;
  final int completedOperations;
  final int reducedCount;
  final String? errorMessage;
  final String? currentOperation;

  const SyncStatusEvent({
    required this.status,
    this.phase = SyncPhase.idle,
    this.totalOperations = 0,
    this.completedOperations = 0,
    this.reducedCount = 0,
    this.errorMessage,
    this.currentOperation,
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
  final _conflictController = StreamController<SyncConflict>.broadcast();
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

  /// Conflicts raised as they are detected.
  ///
  /// Live only: a listener attached later will not see earlier conflicts, so
  /// read `OfflineStore.getConflicts()` on startup and use this to stay
  /// current.
  Stream<SyncConflict> get conflictStream => _conflictController.stream;

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
      // Phase 1: Preparing - Get all pending operations
      _emitPhase(SyncPhase.preparing);
      var pendingOps = await _operationLog.getPendingOperations();
      final initialCount = pendingOps.length;

      if (pendingOps.isEmpty) {
        _emitPhase(SyncPhase.completed);
        _updateStatus(SyncStatus.idle);
        _isSyncing = false;
        return;
      }

      int reducedCount = 0;

      // Phase 2: Reducing - Optionally reduce operations
      if (_config.enableOperationReduction) {
        _emitPhase(SyncPhase.reducing, totalOperations: initialCount);
        pendingOps = await _reduceOperations(pendingOps);
        reducedCount = initialCount - pendingOps.length;
      }

      // Phase 3: Syncing - Send operations to remote
      _emitProgress(pendingOps.length, 0, reducedCount: reducedCount, phase: SyncPhase.syncing);

      // Sync operations in order
      int completed = 0;

      /// Entities whose queue is stalled for the rest of this pass: once a
      /// write is refused as conflicting or rejected outright, every later
      /// write to the same entity is built on the same bad assumption. Sending
      /// them anyway would pile up failures — and, worse, could apply half of a
      /// sequence. Other entities keep syncing normally.
      final stalledEntities = <String>{};

      for (final operation in pendingOps) {
        final entityKey = '${operation.entityType}:${operation.entityId}';
        if (stalledEntities.contains(entityKey)) {
          // Se deja pendiente a propósito: vuelve a intentarse en la próxima
          // pasada, una vez resuelto lo que bloqueó a esta entidad.
          continue;
        }

        final operationDesc = '${operation.operationType.name} ${operation.entityType}';
        _emitProgress(
          pendingOps.length,
          completed,
          reducedCount: reducedCount,
          phase: SyncPhase.syncing,
          currentOperation: operationDesc,
        );

        final outcome = await _syncOperation(operation);
        if (outcome == _SyncOutcome.stalled) {
          stalledEntities.add(entityKey);
        }
        final success = outcome == _SyncOutcome.synced;

        if (!success && _config.stopOnError) {
          _updateStatus(
            SyncStatus.error,
            errorMessage: 'Sync stopped due to error',
          );
          _isSyncing = false;
          return;
        }

        completed++;
        _emitProgress(
          pendingOps.length,
          completed,
          reducedCount: reducedCount,
          phase: SyncPhase.syncing,
        );
      }

      // Save last sync time
      await _storage.saveMetadata('lastSyncTime', DateTime.now().millisecondsSinceEpoch);

      // Phase 4: Completed
      _emitPhase(SyncPhase.completed);
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

      if (reducedOps.length == entityOps.length) {
        // Nothing was reduced — every reduction drops at least one operation,
        // so an unchanged count means the list came back untouched. Squashing
        // here would rewrite the log with what it already holds, and a squash
        // is a delete plus an insert: any per-row bookkeeping a StorageAdapter
        // keeps (attempt counters, timestamps) is reset every single pass, so
        // no attempt cap built on it can ever reach its limit.
        reduced.addAll(entityOps);
      } else if (reducedOps.isNotEmpty) {
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
  Future<_SyncOutcome> _syncOperation(Operation operation) async {
    final adapter = _adapters[operation.entityType];
    if (adapter == null) {
      // A missing adapter is a wiring mistake, not a transient error: retrying
      // it every sync would never register the adapter.
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failedPermanent,
          errorMessage: 'No adapter registered for ${operation.entityType}',
        ),
      );
      return _SyncOutcome.stalled;
    }

    // Mark as syncing
    await _operationLog.update(
      operation.copyWith(status: OperationStatus.syncing),
    );

    try {
      // Send to remote
      final result = await adapter.syncOperation(operation);

      if (result.success) {
        // El servidor ya aplicó la escritura. Reconciliar la copia local es lo
        // que queda, y su fallo no puede reencolar la operación: reenviarla
        // volvería a aplicar en el servidor algo que ya está aplicado, y como
        // la baja del log ocurre igual, el ciclo se repetiría en cada sync sin
        // llegar nunca a agotarse. Una copia local desactualizada, en cambio,
        // se corrige sola en la próxima lectura (son local-first con refresco).
        if (result.resolvedPayload != null) {
          try {
            await _storage.saveEntity(
              operation.entityType,
              operation.entityId,
              result.resolvedPayload!,
            );
          } catch (e) {
            _emitReconcileFailure(operation, e);
          }
        }

        await _operationLog.remove(operation.operationId);

        return _SyncOutcome.synced;
      } else if (result.conflictData != null || result.serverVersion != null) {
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

  /// Handle a write the server refused as conflicting.
  ///
  /// A configured [ConflictResolver] gets first say; anything it declines to
  /// settle — and everything when no resolver is configured — is parked for a
  /// person to decide. Parking rather than failing is what keeps the write
  /// recoverable instead of silently stuck.
  Future<_SyncOutcome> _handleConflict(
    Operation operation,
    SyncResult result,
    RemoteAdapter<dynamic> adapter,
  ) async {
    Map<String, dynamic>? serverState = result.conflictData;
    if (serverState == null) {
      // El backend rechazó sin devolver su estado. Sin estado no hay conflicto
      // que mostrar, sólo un error opaco — vale la pena una llamada extra.
      try {
        serverState = await adapter.fetchRemoteState(operation.entityId);
      } catch (_) {
        // Se sigue sin estado remoto: el conflicto se puede descartar o
        // reintentar, pero no comparar.
      }
    }

    try {
      final resolution = await _autoResolve(operation, serverState, result);
      if (resolution != null) {
        return await _applyResolution(operation, resolution, serverState, result);
      }
    } catch (e) {
      // Que un resolver automático falle no debe perder la operación: se
      // estaciona igual y decide una persona.
      await _park(operation, serverState, result, 'Conflict resolution failed: $e');
      return _SyncOutcome.stalled;
    }

    await _park(operation, serverState, result, result.errorMessage);
    return _SyncOutcome.stalled;
  }

  /// Ask the configured resolver what to do, or null to defer to a person.
  Future<Resolution?> _autoResolve(
    Operation operation,
    Map<String, dynamic>? serverState,
    SyncResult result,
  ) async {
    if (_conflictResolver == null || serverState == null) return null;

    final localData = await _storage.getEntity(
      operation.entityType,
      operation.entityId,
    );
    // La entidad ya no está local: no hay "lo mío" con qué comparar, así que
    // ninguna estrategia automática puede decidir con fundamento.
    if (localData == null) return null;

    final pendingOps = await _operationLog.getOperationsForEntity(
      operation.entityType,
      operation.entityId,
    );

    return _conflictResolver!.resolve(
      LocalState(data: localData, timestamp: operation.timestamp),
      RemoteState(
        data: serverState,
        timestamp: result.serverTimestamp ?? DateTime.now().millisecondsSinceEpoch,
      ),
      pendingOps,
    );
  }

  /// Apply conflict resolution
  Future<_SyncOutcome> _applyResolution(
    Operation operation,
    Resolution resolution,
    Map<String, dynamic>? serverState,
    SyncResult result,
  ) async {
    switch (resolution.strategy) {
      case ResolutionStrategy.useLocal:
        // Rebase antes de reencolar: reenviarla tal cual chocaría contra el
        // mismo chequeo de versión, una y otra vez.
        await _operationLog.update(
          operation.rebased(baseVersion: result.serverVersion),
        );
        return _SyncOutcome.stalled;

      case ResolutionStrategy.useRemote:
        if (serverState != null) {
          await _storage.saveEntity(
            operation.entityType,
            operation.entityId,
            serverState,
          );
        }
        await _operationLog.remove(operation.operationId);
        return _SyncOutcome.synced;

      case ResolutionStrategy.merge:
        if (resolution.mergedData == null) {
          await _park(operation, serverState, result, 'Merge produced no data');
          return _SyncOutcome.stalled;
        }
        await _storage.saveEntity(
          operation.entityType,
          operation.entityId,
          resolution.mergedData!,
        );
        await _operationLog.update(
          operation.rebased(
            baseVersion: result.serverVersion,
            payload: resolution.mergedData,
          ),
        );
        return _SyncOutcome.stalled;

      case ResolutionStrategy.manual:
        await _park(operation, serverState, result, 'Manual conflict resolution required');
        return _SyncOutcome.stalled;
    }
  }

  /// Park a conflicting operation until someone settles it.
  Future<void> _park(
    Operation operation,
    Map<String, dynamic>? serverState,
    SyncResult result,
    String? errorMessage,
  ) async {
    final parked = operation.copyWith(
      status: OperationStatus.conflicted,
      conflictData: serverState,
      conflictServerVersion: result.serverVersion,
      errorMessage: errorMessage,
    );
    await _operationLog.update(parked);
    _conflictController.add(SyncConflict(parked));
  }

  /// Handle sync failure
  Future<_SyncOutcome> _handleFailure(Operation operation, SyncResult result) async {
    if (!result.isRetryable) {
      // Retrying cannot fix this (4xx, validation, business rule): park it
      // permanently instead of re-sending it on every sync forever.
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failedPermanent,
          errorMessage: result.errorMessage,
        ),
      );
      return _SyncOutcome.stalled;
    } else if (operation.retryCount >= _config.maxRetries) {
      // Retryable but out of attempts for now; a later sync may pick it up.
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failed,
          errorMessage: result.errorMessage,
        ),
      );
      return _SyncOutcome.retryable;
    } else {
      // Retry later
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.pending,
          retryCount: operation.retryCount + 1,
          errorMessage: result.errorMessage,
        ),
      );
      return _SyncOutcome.retryable;
    }
  }

  /// Handle exception during sync
  ///
  /// An adapter that throws instead of returning a [SyncResult] broke the
  /// contract, and with it the only source of truth about whether the failure
  /// is worth retrying — the adapter is the one that knows. Treating the
  /// unknown as retryable forever is the worst option available: the queue
  /// never drains, and everything gated on "nothing pending" (logging out,
  /// switching tenants) stays blocked. So it is retried like any transient
  /// failure, and once the attempts are spent it is parked as permanent and
  /// surfaced through [OfflineStore.getFailedOperations] for a person to
  /// retry or discard.
  Future<_SyncOutcome> _handleException(Operation operation, Object error) async {
    if (operation.retryCount >= _config.maxRetries) {
      await _operationLog.update(
        operation.copyWith(
          status: OperationStatus.failedPermanent,
          errorMessage: error.toString(),
        ),
      );
      return _SyncOutcome.stalled;
    }

    await _operationLog.update(
      operation.copyWith(
        status: OperationStatus.pending,
        retryCount: operation.retryCount + 1,
        errorMessage: error.toString(),
      ),
    );
    return _SyncOutcome.retryable;
  }

  void _updateStatus(SyncStatus status, {String? errorMessage}) {
    _currentStatus = status;
    _statusController.add(
      SyncStatusEvent(
        status: status,
        phase: status == SyncStatus.idle ? SyncPhase.idle : SyncPhase.syncing,
        errorMessage: errorMessage,
      ),
    );
  }

  void _emitProgress(
    int total,
    int completed, {
    int reducedCount = 0,
    SyncPhase phase = SyncPhase.syncing,
    String? currentOperation,
  }) {
    _statusController.add(
      SyncStatusEvent(
        status: SyncStatus.syncing,
        phase: phase,
        totalOperations: total,
        completedOperations: completed,
        reducedCount: reducedCount,
        currentOperation: currentOperation,
      ),
    );
  }

  /// Avisa que la copia local no pudo reconciliarse con la respuesta del
  /// servidor, sin marcar el sync como fallido: la escritura remota sí se
  /// aplicó. Va por el stream de estado —el único canal que expone el motor—
  /// para que el fallo no quede mudo, que es lo que lo vuelve difícil de ver.
  void _emitReconcileFailure(Operation operation, Object error) {
    _statusController.add(
      SyncStatusEvent(
        status: SyncStatus.syncing,
        phase: SyncPhase.syncing,
        currentOperation: '${operation.operationType.name} ${operation.entityType}',
        errorMessage:
            'Synced, but saving the server response failed for '
            '${operation.entityType}/${operation.entityId}: $error',
      ),
    );
  }

  void _emitPhase(SyncPhase phase, {int totalOperations = 0}) {
    _statusController.add(
      SyncStatusEvent(
        status: phase == SyncPhase.idle || phase == SyncPhase.completed
            ? SyncStatus.idle
            : SyncStatus.syncing,
        phase: phase,
        totalOperations: totalOperations,
      ),
    );
  }

  void dispose() {
    _statusController.close();
    _conflictController.close();
  }
}
