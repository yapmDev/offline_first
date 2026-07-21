import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

/// Records what it was asked to send, and answers with whatever the test set.
class RecordingRemoteAdapter extends RemoteAdapter<Map<String, dynamic>> {
  RecordingRemoteAdapter(this.result, {this.remoteState});

  SyncResult result;
  Map<String, dynamic>? remoteState;
  final List<Operation> sent = [];
  int fetchRemoteStateCalls = 0;

  @override
  String get entityType => 'test';

  SyncResult _record(Operation operation) {
    sent.add(operation);
    return result;
  }

  @override
  Future<SyncResult> create(Operation operation) async => _record(operation);

  @override
  Future<SyncResult> update(Operation operation) async => _record(operation);

  @override
  Future<SyncResult> delete(Operation operation) async => _record(operation);

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async {
    fetchRemoteStateCalls++;
    return remoteState;
  }
}

const _serverState = {'id': 'entity-1', 'name': 'Theirs', 'version': 7};

void main() {
  late InMemoryStorageAdapter storage;
  late RecordingRemoteAdapter adapter;
  late OfflineStore store;

  Future<void> build({
    SyncResult? result,
    Map<String, dynamic>? remoteState,
    ConflictResolver? resolver,
  }) async {
    storage = InMemoryStorageAdapter();
    adapter = RecordingRemoteAdapter(
      result ?? SyncResult.conflict(conflictData: _serverState, serverVersion: 7),
      remoteState: remoteState,
    );
    store = await OfflineStore.init(
      storage: storage,
      adapters: {'test': adapter},
      conflictResolver: resolver,
      config: const OfflineStoreConfig(deviceId: 'test-device'),
    );
  }

  /// A local edit made on top of version 3, which the server has moved past.
  Future<void> logStaleEdit({String entityId = 'entity-1'}) async {
    await storage.saveEntity('test', entityId, {'id': entityId, 'name': 'Mine'});
    await store.logUpdate('test', entityId, {'name': 'Mine'}, baseVersion: 3);
  }

  tearDown(() async => store.close());

  group('detection', () {
    setUp(() async {
      await build();
      await logStaleEdit();
    });

    test('parks the write as conflicted, not failed', () async {
      await store.sync();

      final conflicts = await store.getConflicts();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.operation.status, OperationStatus.conflicted);
      expect(conflicts.single.serverState, _serverState);
      expect(conflicts.single.serverVersion, 7);
      expect(conflicts.single.baseVersion, 3);
      expect(conflicts.single.localPayload, {'name': 'Mine'});
    });

    test('does not resend it on later syncs', () async {
      await store.sync();
      await store.sync();
      await store.sync();

      expect(adapter.sent, hasLength(1),
          reason: 'a conflict is settled by a decision, not by retrying');
      expect(await store.getPendingOperationsCount(), 0);
    });

    test('announces it on the conflict stream', () async {
      final seen = <SyncConflict>[];
      store.conflictStream.listen(seen.add);

      await store.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(seen, hasLength(1));
      expect(seen.single.entityId, 'entity-1');
    });

    test('survives a restart, keeping the state the write lost against',
        () async {
      await store.sync();
      await store.close();

      // Mismo storage, store nuevo: lo que sobreviva salió de disco.
      store = await OfflineStore.init(
        storage: storage,
        adapters: {'test': adapter},
        config: const OfflineStoreConfig(deviceId: 'test-device'),
      );

      final conflicts = await store.getConflicts();
      expect(conflicts.single.serverState, _serverState);
      expect(conflicts.single.serverVersion, 7);
    });

    test('falls back to fetchRemoteState when the server sends no state',
        () async {
      await build(
        result: const SyncResult(success: false, serverVersion: 9, isRetryable: false),
        remoteState: _serverState,
      );
      await logStaleEdit();

      await store.sync();

      expect(adapter.fetchRemoteStateCalls, 1);
      expect((await store.getConflicts()).single.serverState, _serverState);
    });
  });

  group('entity stalling', () {
    test('holds back later writes to the same entity, but not to others',
        () async {
      await build();
      await logStaleEdit();
      await store.logUpdate('test', 'entity-1', {'name': 'Mine again'},
          baseVersion: 3);
      await store.logUpdate('test', 'entity-2', {'name': 'Unrelated'},
          baseVersion: 1);

      await store.sync();

      final touched = adapter.sent.map((op) => op.entityId).toSet();
      expect(touched, {'entity-1', 'entity-2'},
          reason: 'an unrelated entity must keep syncing');
      expect(adapter.sent.where((op) => op.entityId == 'entity-1'), hasLength(1),
          reason: 'the second edit was built on the same stale assumption');
    });
  });

  group('resolveConflict', () {
    setUp(() async {
      await build();
      await logStaleEdit();
      await store.sync();
    });

    test('keepLocal rebases onto the server version so the retry lands',
        () async {
      final conflict = (await store.getConflicts()).single;
      await store.resolveConflict(conflict.operationId, ConflictChoice.keepLocal);

      expect(await store.getConflicts(), isEmpty);
      expect(await store.getPendingOperationsCount(), 1);

      adapter.result = SyncResult.success();
      await store.sync();

      expect(adapter.sent.last.baseVersion, 7,
          reason: 'resending the stale version would conflict all over again');
      expect(await store.getPendingOperationsCount(), 0);
    });

    test('keepLocal can replace the payload, which is how a merge lands',
        () async {
      final conflict = (await store.getConflicts()).single;
      await store.resolveConflict(
        conflict.operationId,
        ConflictChoice.keepLocal,
        payload: {'name': 'Merged'},
      );

      adapter.result = SyncResult.success();
      await store.sync();

      expect(adapter.sent.last.payload, {'name': 'Merged'});
      expect(adapter.sent.last.baseVersion, 7);
    });

    test('keepRemote adopts the server state and drops the write', () async {
      final conflict = (await store.getConflicts()).single;
      await store.resolveConflict(conflict.operationId, ConflictChoice.keepRemote);

      expect(await storage.getEntity('test', 'entity-1'), _serverState);
      expect(await store.getConflicts(), isEmpty);
      expect(await store.getPendingOperationsCount(), 0);
    });

    test('discard drops the write and leaves local state alone', () async {
      final conflict = (await store.getConflicts()).single;
      await store.resolveConflict(conflict.operationId, ConflictChoice.discard);

      expect(await storage.getEntity('test', 'entity-1'),
          {'id': 'entity-1', 'name': 'Mine'});
      expect(await store.getConflicts(), isEmpty);
      expect(await store.getPendingOperationsCount(), 0);
    });

    test('refuses to settle the same conflict twice', () async {
      final conflict = (await store.getConflicts()).single;
      await store.resolveConflict(conflict.operationId, ConflictChoice.discard);

      expect(
        () => store.resolveConflict(conflict.operationId, ConflictChoice.keepLocal),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('automatic resolver', () {
    test('LastWriteWins adopts the newer server state without parking anything',
        () async {
      // El adapter DEBE mandar `serverTimestamp`: sin él el motor cae al reloj
      // local, ambos lados quedan en el mismo milisegundo y la comparación se
      // vuelve una moneda al aire.
      await build(
        resolver: LastWriteWinsResolver(),
        result: SyncResult.conflict(
          conflictData: _serverState,
          serverVersion: 7,
          serverTimestamp: DateTime.now().millisecondsSinceEpoch + 60000,
        ),
      );
      await logStaleEdit();

      await store.sync();

      expect(await store.getConflicts(), isEmpty);
      expect(await storage.getEntity('test', 'entity-1'), _serverState);
    });

    test('LastWriteWins keeping the newer local edit rebases it for a retry',
        () async {
      await build(
        resolver: LastWriteWinsResolver(),
        result: SyncResult.conflict(
          conflictData: _serverState,
          serverVersion: 7,
          serverTimestamp: DateTime.now().millisecondsSinceEpoch - 60000,
        ),
      );
      await logStaleEdit();

      await store.sync();
      adapter.result = SyncResult.success();
      await store.sync();

      expect(adapter.sent.last.baseVersion, 7,
          reason: 'keeping the local edit must rebase, or it conflicts forever');
      expect(await store.getPendingOperationsCount(), 0);
    });

    test('parks the conflict when the entity is gone locally', () async {
      await build(resolver: LastWriteWinsResolver());
      await store.logUpdate('test', 'entity-1', {'name': 'Mine'}, baseVersion: 3);

      await store.sync();

      expect((await store.getConflicts()), hasLength(1),
          reason: 'with nothing local to compare, no strategy can decide');
    });
  });

  group('operation persistence', () {
    test('carries baseVersion and conflict data through storage', () async {
      const original = Operation(
        operationId: 'op-1',
        entityType: 'test',
        entityId: 'entity-1',
        operationType: OperationType.update,
        payload: {'name': 'Mine'},
        timestamp: 1,
        status: OperationStatus.conflicted,
        deviceId: 'test-device',
        baseVersion: 3,
        conflictData: _serverState,
        conflictServerVersion: 7,
      );

      final restored = Operation.fromMap(original.toMap());

      expect(restored.baseVersion, 3);
      expect(restored.conflictData, _serverState);
      expect(restored.conflictServerVersion, 7);
      expect(restored.status, OperationStatus.conflicted);
    });

    test('rebasing clears the conflict and resets the attempt count', () async {
      const conflicted = Operation(
        operationId: 'op-1',
        entityType: 'test',
        entityId: 'entity-1',
        operationType: OperationType.update,
        payload: {'name': 'Mine'},
        timestamp: 1,
        status: OperationStatus.conflicted,
        deviceId: 'test-device',
        retryCount: 2,
        baseVersion: 3,
        conflictData: _serverState,
        conflictServerVersion: 7,
      );

      final rebased = conflicted.rebased(baseVersion: 7);

      expect(rebased.status, OperationStatus.pending);
      expect(rebased.baseVersion, 7);
      expect(rebased.conflictData, isNull);
      expect(rebased.conflictServerVersion, isNull);
      expect(rebased.retryCount, 0);
      expect(rebased.operationId, 'op-1', reason: 'idempotency key must survive');
    });
  });
}
