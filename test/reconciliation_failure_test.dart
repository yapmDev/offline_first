import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

/// Storage that accepts everything except saving an entity — the shape of a
/// local write that fails after the remote one already succeeded (a cache model
/// rejecting a field the backend just added, an entity type the app forgot to
/// route).
class SaveHostileStorage extends InMemoryStorageAdapter {
  @override
  Future<void> saveEntity(
    String entityType,
    String entityId,
    Map<String, dynamic> data,
  ) async {
    throw StateError('cannot store $entityType/$entityId');
  }
}

class EchoRemoteAdapter extends RemoteAdapter<Map<String, dynamic>> {
  int attempts = 0;

  @override
  String get entityType => 'test';

  SyncResult _record(Operation operation) {
    attempts++;
    return SyncResult.success(resolvedPayload: {'id': operation.entityId});
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

/// Reconciling the server's response is the last step of a sync, and by then the
/// write is already applied remotely. Treating a failure there as a failed sync
/// re-queues an operation the server has accepted: the next pass sends it again,
/// fails to reconcile again, and re-queues again — forever, since the operation
/// leaves the log on every pass and takes its retry bookkeeping with it.
void main() {
  late SaveHostileStorage storage;
  late EchoRemoteAdapter adapter;
  late OfflineStore store;

  setUp(() async {
    storage = SaveHostileStorage();
    adapter = EchoRemoteAdapter();
    store = await OfflineStore.init(
      storage: storage,
      adapters: {'test': adapter},
      config: const OfflineStoreConfig(deviceId: 'test-device'),
    );
    await store.logCreate('test', 'entity-1', {'name': 'Test'});
  });

  tearDown(() async => store.close());

  test('a write the server applied leaves the queue', () async {
    await store.sync();

    expect(await store.getPendingOperationsCount(), 0);
    expect(await storage.getOperationsForType('test'), isEmpty);
  });

  test('a write the server applied is never sent twice', () async {
    await store.sync();
    await store.sync();

    expect(adapter.attempts, 1);
  });

  test('the failure is reported without failing the sync', () async {
    final events = <SyncStatusEvent>[];
    final sub = store.syncStatusStream.listen(events.add);

    await store.sync();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(
      events.where((e) => e.errorMessage != null),
      isNotEmpty,
      reason: 'a silent local failure is what made this hard to find',
    );
    expect(events.map((e) => e.status), isNot(contains(SyncStatus.error)));
  });
}
