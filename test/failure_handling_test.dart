import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

/// Adapter whose result is decided per test.
class ConfigurableRemoteAdapter extends RemoteAdapter<Map<String, dynamic>> {
  ConfigurableRemoteAdapter(this.result);

  SyncResult result;
  int attempts = 0;

  @override
  String get entityType => 'test';

  SyncResult _record(Operation operation) {
    attempts++;
    return result;
  }

  @override
  Future<SyncResult> create(Operation operation) async => _record(operation);

  @override
  Future<SyncResult> update(Operation operation) async => _record(operation);

  @override
  Future<SyncResult> delete(Operation operation) async => _record(operation);

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async => null;
}

void main() {
  late InMemoryStorageAdapter storage;
  late ConfigurableRemoteAdapter adapter;
  late OfflineStore store;

  Future<OfflineStore> buildStore(SyncResult result) async {
    storage = InMemoryStorageAdapter();
    adapter = ConfigurableRemoteAdapter(result);
    return OfflineStore.init(
      storage: storage,
      adapters: {'test': adapter},
      config: const OfflineStoreConfig(deviceId: 'test-device'),
    );
  }

  Future<Operation> onlyOperation() async {
    final all = await storage.getOperationsForType('test');
    expect(all.length, 1);
    return all.first;
  }

  tearDown(() async => store.close());

  group('non-retryable failure', () {
    setUp(() async {
      store = await buildStore(
        SyncResult.failure(errorMessage: 'Duplicate name', isRetryable: false),
      );
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
    });

    test('is parked as failedPermanent instead of failed', () async {
      await store.sync();

      expect((await onlyOperation()).status, OperationStatus.failedPermanent);
    });

    test('is never attempted again on later syncs', () async {
      await store.sync();
      expect(adapter.attempts, 1);

      await store.sync();
      await store.sync();

      expect(adapter.attempts, 1, reason: 'permanent failure must not retry');
      expect(await store.getPendingOperationsCount(), 0);
    });
  });

  group('retryable failure', () {
    setUp(() async {
      store = await buildStore(
        SyncResult.failure(errorMessage: 'Connection reset'),
      );
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
    });

    test('exhausts maxRetries and then stays eligible for a new attempt',
        () async {
      // maxRetries defaults to 3: attempts 1..3 keep it pending, the 4th
      // parks it as `failed`.
      for (var i = 0; i < 4; i++) {
        await store.sync();
      }

      expect((await onlyOperation()).status, OperationStatus.failed);
      expect(await store.getPendingOperationsCount(), 1);

      await store.sync();
      expect(adapter.attempts, 5,
          reason: 'a retryable failure is worth trying again later');
    });

    test('recovers once the remote stops failing', () async {
      await store.sync();
      adapter.result = SyncResult.success();
      await store.sync();

      expect(await storage.getOperationsForType('test'), isEmpty);
      expect(await store.getPendingOperationsCount(), 0);
    });
  });

  group('orphaned operation', () {
    test('left in syncing by a dead process is revived', () async {
      store = await buildStore(SyncResult.success());
      await storage.addOperation(
        const Operation(
          operationId: 'op-orphan',
          entityType: 'test',
          entityId: 'entity-1',
          operationType: OperationType.update,
          payload: {'name': 'Test'},
          timestamp: 1,
          status: OperationStatus.syncing,
          deviceId: 'test-device',
        ),
      );

      expect(await store.getPendingOperationsCount(), 1);

      await store.sync();

      expect(adapter.attempts, 1);
      expect(await storage.getOperationsForType('test'), isEmpty);
    });
  });

  group('unsyncedEntityIds', () {
    setUp(() async {
      store = await buildStore(
        SyncResult.failure(errorMessage: 'Duplicate name', isRetryable: false),
      );
    });

    test('reports entities with a local write the server has not seen',
        () async {
      await store.save('test', 'entity-1', {'name': 'A'}, isNew: true);

      expect(await store.unsyncedEntityIds('test'), {'entity-1'});
      expect(await store.unsyncedEntityIds('other'), isEmpty);
    });

    test('still reports them after a permanent failure', () async {
      await store.save('test', 'entity-1', {'name': 'A'}, isNew: true);
      await store.sync();

      expect((await onlyOperation()).status, OperationStatus.failedPermanent);
      expect(await store.unsyncedEntityIds('test'), {'entity-1'},
          reason: 'a refresh must not prune an id the server never got');
    });

    test('drops them once the operation syncs', () async {
      adapter.result = SyncResult.success();
      await store.save('test', 'entity-1', {'name': 'A'}, isNew: true);
      await store.sync();

      expect(await store.unsyncedEntityIds('test'), isEmpty);
    });
  });
}
