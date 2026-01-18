import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

class MockRemoteAdapter extends RemoteAdapter<Map<String, dynamic>> {
  final List<Operation> processedOperations = [];

  @override
  String get entityType => 'test';

  @override
  Future<SyncResult> create(Operation operation) async {
    processedOperations.add(operation);
    return SyncResult.success();
  }

  @override
  Future<SyncResult> update(Operation operation) async {
    processedOperations.add(operation);
    return SyncResult.success();
  }

  @override
  Future<SyncResult> delete(Operation operation) async {
    processedOperations.add(operation);
    return SyncResult.success();
  }

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async {
    return null;
  }
}

void main() {
  group('OfflineStore', () {
    late OfflineStore store;
    late MockRemoteAdapter adapter;

    setUp(() async {
      final storage = InMemoryStorageAdapter();
      adapter = MockRemoteAdapter();

      store = await OfflineStore.init(
        storage: storage,
        adapters: {'test': adapter},
        config: const OfflineStoreConfig(deviceId: 'test-device'),
      );
    });

    tearDown(() async {
      await store.close();
    });

    test('should save entity and create operation', () async {
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);

      final entity = await store.get('test', 'entity-1');
      final pendingCount = await store.getPendingOperationsCount();

      expect(entity, isNotNull);
      expect(entity!['name'], 'Test');
      expect(pendingCount, 1);
    });

    test('should update entity', () async {
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
      await store.save('test', 'entity-1', {'name': 'Updated'});

      final entity = await store.get('test', 'entity-1');
      final pendingCount = await store.getPendingOperationsCount();

      expect(entity!['name'], 'Updated');
      expect(pendingCount, 2);
    });

    test('should delete entity', () async {
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
      await store.delete('test', 'entity-1');

      final entity = await store.get('test', 'entity-1');
      final pendingCount = await store.getPendingOperationsCount();

      expect(entity, isNull);
      expect(pendingCount, 2); // create + delete
    });

    test('should sync operations', () async {
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
      await store.save('test', 'entity-2', {'name': 'Test2'}, isNew: true);

      await store.sync();

      final pendingCount = await store.getPendingOperationsCount();
      expect(pendingCount, 0);
      expect(adapter.processedOperations.length, 2);
    });

    test('should get all entities of type', () async {
      await store.save('test', 'entity-1', {'name': 'A'}, isNew: true);
      await store.save('test', 'entity-2', {'name': 'B'}, isNew: true);

      final entities = await store.getAll('test');

      expect(entities.length, 2);
    });

    test('should emit sync status events', () async {
      await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);

      final events = <SyncStatusEvent>[];
      store.syncStatusStream.listen(events.add);

      await store.sync();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(events.isNotEmpty, true);
      expect(events.any((e) => e.status == SyncStatus.syncing), true);
      expect(events.any((e) => e.status == SyncStatus.idle), true);
    });
  });
}
