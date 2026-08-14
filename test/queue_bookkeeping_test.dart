import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

/// Storage that keeps per-row bookkeeping, the way a real adapter does to cap
/// how many times an operation may fail before it stops counting as pending.
///
/// The counter lives with the row, so it is lost whenever the row is deleted
/// and inserted again — which is exactly what a squash does.
class _CountingStorage extends InMemoryStorageAdapter {
  final Map<String, int> attempts = {};
  int inserts = 0;

  @override
  Future<void> addOperation(Operation operation) async {
    inserts++;
    attempts[operation.operationId] = 0;
    await super.addOperation(operation);
  }

  @override
  Future<void> updateOperation(Operation operation) async {
    if (operation.status == OperationStatus.failed) {
      attempts[operation.operationId] =
          (attempts[operation.operationId] ?? 0) + 1;
    }
    await super.updateOperation(operation);
  }
}

/// Adapter that throws instead of returning a [SyncResult] — the contract
/// violation a mapping bug produces in practice.
class _ThrowingAdapter extends RemoteAdapter<Map<String, dynamic>> {
  int attempts = 0;

  @override
  String get entityType => 'test';

  Never _boom() {
    attempts++;
    throw StateError('type cast failed while building the request');
  }

  @override
  Future<SyncResult> create(Operation operation) async => _boom();

  @override
  Future<SyncResult> update(Operation operation) async => _boom();

  @override
  Future<SyncResult> delete(Operation operation) async => _boom();

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async => null;
}

/// Adapter that keeps failing for a reason worth retrying.
class _FlakyAdapter extends RemoteAdapter<Map<String, dynamic>> {
  int attempts = 0;

  @override
  String get entityType => 'test';

  SyncResult _fail() {
    attempts++;
    return SyncResult.failure(errorMessage: 'Connection reset');
  }

  @override
  Future<SyncResult> create(Operation operation) async => _fail();

  @override
  Future<SyncResult> update(Operation operation) async => _fail();

  @override
  Future<SyncResult> delete(Operation operation) async => _fail();

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async => null;
}

void main() {
  group('reduction with nothing to reduce', () {
    late _CountingStorage storage;
    late _FlakyAdapter adapter;
    late OfflineStore store;

    setUp(() async {
      storage = _CountingStorage();
      adapter = _FlakyAdapter();
      store = await OfflineStore.init(
        storage: storage,
        adapters: {'test': adapter},
        config: const OfflineStoreConfig(deviceId: 'test-device'),
      );
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
    });

    tearDown(() async => store.close());

    test('leaves the log alone instead of deleting and re-inserting', () async {
      await store.sync();
      await store.sync();
      await store.sync();

      expect(storage.inserts, 1,
          reason: 'the queued write was inserted once, when it was logged');
    });

    test("keeps the storage's own attempt bookkeeping across syncs", () async {
      // Sin esto, un tope de reintentos por fila se reinicia en cada pasada y
      // la operación se reintenta —y cuenta como pendiente— para siempre.
      for (var i = 0; i < 6; i++) {
        await store.sync();
      }

      final operation = (await storage.getOperationsForType('test')).single;
      expect(storage.attempts[operation.operationId], greaterThan(1));
    });
  });

  group('an adapter that throws', () {
    late InMemoryStorageAdapter storage;
    late _ThrowingAdapter adapter;
    late OfflineStore store;

    setUp(() async {
      storage = InMemoryStorageAdapter();
      adapter = _ThrowingAdapter();
      store = await OfflineStore.init(
        storage: storage,
        adapters: {'test': adapter},
        config: const OfflineStoreConfig(deviceId: 'test-device'),
      );
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
    });

    tearDown(() async => store.close());

    test('stops being retried once the attempts are spent', () async {
      for (var i = 0; i < 10; i++) {
        await store.sync();
      }

      expect(adapter.attempts, 4, reason: 'first try plus maxRetries');
      expect(await store.getPendingOperationsCount(), 0);
    });

    test('is surfaced for a person instead of vanishing', () async {
      for (var i = 0; i < 10; i++) {
        await store.sync();
      }

      final failed = await store.getFailedOperations();
      expect(failed, hasLength(1));
      expect(failed.single.errorMessage, contains('type cast failed'));
    });
  });
}
