# Advanced Usage Guide

This guide covers advanced use cases and patterns for the `offline_first` package.

---

## Custom Storage Adapter

While the package includes `InMemoryStorageAdapter` for testing, production apps need persistent storage. Here's how to implement a custom storage adapter using Hive:

### Hive Storage Adapter Example

```dart
import 'package:hive/hive.dart';
import 'package:offline_first/offline_first.dart';

class HiveStorageAdapter implements StorageAdapter {
  late Box<Map<dynamic, dynamic>> _entitiesBox;
  late Box<Map<dynamic, dynamic>> _operationsBox;
  late Box<dynamic> _metadataBox;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    await Hive.initFlutter();

    _entitiesBox = await Hive.openBox<Map<dynamic, dynamic>>('entities');
    _operationsBox = await Hive.openBox<Map<dynamic, dynamic>>('operations');
    _metadataBox = await Hive.openBox('metadata');

    _initialized = true;
  }

  @override
  Future<void> close() async {
    await _entitiesBox.close();
    await _operationsBox.close();
    await _metadataBox.close();
    _initialized = false;
  }

  @override
  Future<void> saveEntity(
    String entityType,
    String entityId,
    Map<String, dynamic> data,
  ) async {
    final key = '$entityType:$entityId';
    await _entitiesBox.put(key, data);
  }

  @override
  Future<Map<String, dynamic>?> getEntity(
    String entityType,
    String entityId,
  ) async {
    final key = '$entityType:$entityId';
    final data = _entitiesBox.get(key);
    return data?.cast<String, dynamic>();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllEntities(String entityType) async {
    final results = <Map<String, dynamic>>[];

    for (final key in _entitiesBox.keys) {
      if (key.toString().startsWith('$entityType:')) {
        final data = _entitiesBox.get(key);
        if (data != null) {
          results.add(data.cast<String, dynamic>());
        }
      }
    }

    return results;
  }

  @override
  Future<void> deleteEntity(String entityType, String entityId) async {
    final key = '$entityType:$entityId';
    await _entitiesBox.delete(key);
  }

  @override
  Future<bool> entityExists(String entityType, String entityId) async {
    final key = '$entityType:$entityId';
    return _entitiesBox.containsKey(key);
  }

  @override
  Future<void> addOperation(Operation operation) async {
    await _operationsBox.put(operation.operationId, operation.toMap());
  }

  @override
  Future<Operation?> getOperation(String operationId) async {
    final data = _operationsBox.get(operationId);
    if (data == null) return null;
    return Operation.fromMap(data.cast<String, dynamic>());
  }

  @override
  Future<List<Operation>> getPendingOperations() async {
    final operations = <Operation>[];

    for (final data in _operationsBox.values) {
      final op = Operation.fromMap(data.cast<String, dynamic>());
      if (op.status == OperationStatus.pending) {
        operations.add(op);
      }
    }

    operations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return operations;
  }

  @override
  Future<List<Operation>> getOperationsForEntity(
    String entityType,
    String entityId,
  ) async {
    final operations = <Operation>[];

    for (final data in _operationsBox.values) {
      final op = Operation.fromMap(data.cast<String, dynamic>());
      if (op.entityType == entityType && op.entityId == entityId) {
        operations.add(op);
      }
    }

    operations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return operations;
  }

  @override
  Future<void> updateOperation(Operation operation) async {
    await _operationsBox.put(operation.operationId, operation.toMap());
  }

  @override
  Future<void> deleteOperation(String operationId) async {
    await _operationsBox.delete(operationId);
  }

  @override
  Future<void> deleteOperations(List<String> operationIds) async {
    await _operationsBox.deleteAll(operationIds);
  }

  @override
  Future<int> getPendingOperationsCount() async {
    return _operationsBox.values
        .where((data) {
          final op = Operation.fromMap(data.cast<String, dynamic>());
          return op.status == OperationStatus.pending;
        })
        .length;
  }

  @override
  Future<void> saveMetadata(String key, dynamic value) async {
    await _metadataBox.put(key, value);
  }

  @override
  Future<dynamic> getMetadata(String key) async {
    return _metadataBox.get(key);
  }

  @override
  Future<void> clearMetadata() async {
    await _metadataBox.clear();
  }

  @override
  Future<bool> executeTransaction(
    Future<void> Function(StorageAdapter adapter) operations,
  ) async {
    try {
      await operations(this);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clearAll() async {
    await _entitiesBox.clear();
    await _operationsBox.clear();
    await _metadataBox.clear();
  }
}
```

### Usage

```dart
final storage = HiveStorageAdapter();
await storage.initialize();

final store = await OfflineStore.init(
  storage: storage,
  adapters: adapters,
);
```

---

## Custom Conflict Resolver

For domain-specific conflict resolution:

```dart
class InventoryConflictResolver extends ConflictResolver {
  @override
  Future<Resolution> resolve(
    LocalState local,
    RemoteState remote,
    List<Operation> pendingOperations,
  ) async {
    // For inventory, prefer higher stock count
    final localStock = local.data['stock'] as int? ?? 0;
    final remoteStock = remote.data['stock'] as int? ?? 0;

    if (localStock > remoteStock) {
      // Local has more stock, keep local
      return Resolution.useLocal();
    } else if (remoteStock > localStock) {
      // Remote has more stock, use remote
      return Resolution.useRemote();
    } else {
      // Same stock, merge other fields
      final merged = {...remote.data};

      // Keep local name if modified
      if (local.data['name'] != remote.data['name']) {
        merged['name'] = local.data['name'];
      }

      return Resolution.merge(merged);
    }
  }
}
```

---

## Real HTTP Remote Adapter

Here's a production-ready HTTP adapter:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:offline_first/offline_first.dart';

class HttpProductAdapter extends RemoteAdapter<Product> {
  final String baseUrl;
  final String authToken;

  HttpProductAdapter({
    required this.baseUrl,
    required this.authToken,
  });

  @override
  String get entityType => 'product';

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $authToken',
  };

  @override
  Future<SyncResult> create(Operation operation) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/products'),
        headers: {
          ..._headers,
          'X-Operation-Id': operation.operationId,
          'X-Device-Id': operation.deviceId,
        },
        body: jsonEncode(operation.payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncResult.success(
          serverId: data['id'] as String?,
          serverTimestamp: data['timestamp'] as int?,
        );
      } else if (response.statusCode == 409) {
        // Conflict
        final conflictData = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncResult.conflict(conflictData: conflictData);
      } else if (response.statusCode >= 500) {
        // Server error - retryable
        return SyncResult.failure(
          errorMessage: 'Server error: ${response.statusCode}',
          isRetryable: true,
        );
      } else {
        // Client error - not retryable
        return SyncResult.failure(
          errorMessage: 'Request failed: ${response.body}',
          isRetryable: false,
        );
      }
    } catch (e) {
      // Network error - retryable
      return SyncResult.failure(
        errorMessage: e.toString(),
        isRetryable: true,
      );
    }
  }

  @override
  Future<SyncResult> update(Operation operation) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/products/${operation.entityId}'),
        headers: {
          ..._headers,
          'X-Operation-Id': operation.operationId,
          'X-Device-Id': operation.deviceId,
        },
        body: jsonEncode(operation.payload),
      );

      if (response.statusCode == 200) {
        return SyncResult.success();
      } else if (response.statusCode == 409) {
        final conflictData = jsonDecode(response.body) as Map<String, dynamic>;
        return SyncResult.conflict(conflictData: conflictData);
      } else if (response.statusCode >= 500) {
        return SyncResult.failure(
          errorMessage: 'Server error: ${response.statusCode}',
          isRetryable: true,
        );
      } else {
        return SyncResult.failure(
          errorMessage: 'Request failed: ${response.body}',
          isRetryable: false,
        );
      }
    } catch (e) {
      return SyncResult.failure(
        errorMessage: e.toString(),
        isRetryable: true,
      );
    }
  }

  @override
  Future<SyncResult> delete(Operation operation) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/products/${operation.entityId}'),
        headers: {
          ..._headers,
          'X-Operation-Id': operation.operationId,
          'X-Device-Id': operation.deviceId,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return SyncResult.success();
      } else if (response.statusCode >= 500) {
        return SyncResult.failure(
          errorMessage: 'Server error: ${response.statusCode}',
          isRetryable: true,
        );
      } else {
        return SyncResult.failure(
          errorMessage: 'Request failed: ${response.body}',
          isRetryable: false,
        );
      }
    } catch (e) {
      return SyncResult.failure(
        errorMessage: e.toString(),
        isRetryable: true,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/products/$entityId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
```

---

## Automatic Sync on Connectivity Change

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class AutoSyncManager {
  final OfflineStore store;
  final Connectivity connectivity;

  StreamSubscription? _subscription;

  AutoSyncManager({
    required this.store,
    required this.connectivity,
  });

  void start() {
    _subscription = connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _syncWhenReady();
      }
    });
  }

  Future<void> _syncWhenReady() async {
    // Wait a bit for connection to stabilize
    await Future.delayed(const Duration(seconds: 2));

    // Check if there are pending operations
    final pendingCount = await store.getPendingOperationsCount();
    if (pendingCount > 0) {
      try {
        await store.sync();
      } catch (e) {
        print('Auto-sync failed: $e');
      }
    }
  }

  void stop() {
    _subscription?.cancel();
  }
}

// Usage
final autoSync = AutoSyncManager(
  store: store,
  connectivity: Connectivity(),
);
autoSync.start();
```

---

## Custom Operation Reducer

```dart
class AggressiveOperationReducer extends OperationReducer {
  @override
  ReduceResult reduce(Operation first, Operation second) {
    // Try default rules first
    final defaultReducer = DefaultOperationReducer();
    final defaultResult = defaultReducer.reduce(first, second);

    if (defaultResult.wasReduced) {
      return defaultResult;
    }

    // Custom rule: DELETE + CREATE with same data → UPDATE
    if (first.operationType == OperationType.delete &&
        second.operationType == OperationType.create &&
        first.entityId == second.entityId) {
      return ReduceResult.reduced(
        Operation(
          operationId: second.operationId,
          entityType: second.entityType,
          entityId: second.entityId,
          operationType: OperationType.update,
          payload: second.payload,
          timestamp: second.timestamp,
          status: second.status,
          deviceId: second.deviceId,
        ),
      );
    }

    return ReduceResult.notReduced();
  }
}
```

---

## Periodic Sync

```dart
import 'dart:async';

class PeriodicSyncManager {
  final OfflineStore store;
  final Duration interval;

  Timer? _timer;

  PeriodicSyncManager({
    required this.store,
    this.interval = const Duration(minutes: 5),
  });

  void start() {
    _timer = Timer.periodic(interval, (_) => _sync());
  }

  Future<void> _sync() async {
    if (store.isSyncing) return;

    try {
      await store.sync();
    } catch (e) {
      print('Periodic sync failed: $e');
    }
  }

  void stop() {
    _timer?.cancel();
  }
}
```

---

## Monitoring and Logging

```dart
class SyncMonitor {
  final OfflineStore store;

  SyncMonitor(this.store) {
    _setupListeners();
  }

  void _setupListeners() {
    store.syncStatusStream.listen((event) {
      switch (event.status) {
        case SyncStatus.idle:
          print('✅ Sync idle');
          break;
        case SyncStatus.syncing:
          print('🔄 Syncing: ${event.completedOperations}/${event.totalOperations}');
          break;
        case SyncStatus.error:
          print('❌ Sync error: ${event.errorMessage}');
          _logError(event);
          break;
      }
    });
  }

  void _logError(SyncStatusEvent event) {
    // Send to error tracking service
    // e.g., Sentry, Firebase Crashlytics
  }
}
```

---

## Testing Utilities

```dart
class TestHelpers {
  static Future<OfflineStore> createTestStore({
    Map<String, RemoteAdapter>? adapters,
  }) async {
    final storage = InMemoryStorageAdapter();

    return OfflineStore.init(
      storage: storage,
      adapters: adapters ?? {},
      config: const OfflineStoreConfig(
        deviceId: 'test-device',
        syncConfig: SyncConfig(
          enableOperationReduction: true,
        ),
      ),
    );
  }

  static Operation createTestOperation({
    String? id,
    String entityType = 'test',
    String entityId = 'test-1',
    OperationType type = OperationType.create,
    Map<String, dynamic>? payload,
  }) {
    return Operation(
      operationId: id ?? 'op-${DateTime.now().millisecondsSinceEpoch}',
      entityType: entityType,
      entityId: entityId,
      operationType: type,
      payload: payload ?? {},
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: OperationStatus.pending,
      deviceId: 'test-device',
    );
  }
}

// Usage in tests
test('should sync operations', () async {
  final store = await TestHelpers.createTestStore(
    adapters: {'test': MockAdapter()},
  );

  await store.save('test', 'entity-1', {'name': 'Test'}, isNew: true);
  await store.sync();

  final pending = await store.getPendingOperationsCount();
  expect(pending, 0);
});
```

---

## GraphQL Adapter Example

```dart
import 'package:graphql/client.dart';

class GraphQLProductAdapter extends RemoteAdapter<Product> {
  final GraphQLClient client;

  GraphQLProductAdapter(this.client);

  @override
  String get entityType => 'product';

  @override
  Future<SyncResult> create(Operation operation) async {
    const mutation = '''
      mutation CreateProduct(\$input: ProductInput!, \$operationId: ID!) {
        createProduct(input: \$input, operationId: \$operationId) {
          id
          timestamp
        }
      }
    ''';

    try {
      final result = await client.mutate(
        MutationOptions(
          document: gql(mutation),
          variables: {
            'input': operation.payload,
            'operationId': operation.operationId,
          },
        ),
      );

      if (result.hasException) {
        return SyncResult.failure(
          errorMessage: result.exception.toString(),
        );
      }

      return SyncResult.success(
        serverId: result.data?['createProduct']?['id'] as String?,
        serverTimestamp: result.data?['createProduct']?['timestamp'] as int?,
      );
    } catch (e) {
      return SyncResult.failure(errorMessage: e.toString());
    }
  }

  // Similar implementations for update, delete...
}
```

---

## Best Practices

1. **Always implement idempotency** in your remote adapters
2. **Use persistent storage** in production (not InMemory)
3. **Handle all error cases** (network, server, client errors)
4. **Monitor sync failures** and alert if they persist
5. **Test offline scenarios** thoroughly
6. **Encrypt sensitive data** in storage
7. **Implement proper authentication** in adapters
8. **Set reasonable retry limits** to avoid infinite loops
9. **Clean up old synced operations** periodically
10. **Use operation squashing** to optimize network usage

---

## Performance Tips

- Enable operation reduction to minimize sync operations
- Use batch sync when backend supports it
- Implement pagination for large datasets
- Add indexes to storage for faster queries
- Compress large payloads before syncing
- Use connection pooling in HTTP adapters
- Cache frequently accessed entities in memory

---

## Security Considerations

- Store sensitive data encrypted
- Use HTTPS for all remote communication
- Implement proper authentication in adapters
- Validate operation payloads
- Sanitize user input before creating operations
- Use secure storage on mobile platforms
- Implement rate limiting for sync operations

---

Happy building! 🚀
