# offline_first

A generic, reusable **offline-first architecture** package for Dart/Flutter based on **operation-log**, featuring **incremental sync**, **operation squashing**, **idempotency**, and **pluggable remote adapters**.

## Features

✅ **Operation-based sync** - No snapshots, only domain operations
✅ **Local-first** - Local storage is always the source of truth
✅ **Incremental sync** - Sync only changes, not entire datasets
✅ **Operation squashing** - Automatic optimization of operation queues
✅ **Idempotent** - Safe against retries, duplicates, and failures
✅ **Transport agnostic** - Works with REST, GraphQL, gRPC, or any backend
✅ **Conflict resolution** - Pluggable conflict resolution strategies
✅ **Storage agnostic** - Use any storage backend (Hive, SQLite, etc.)
✅ **Code generation** - Reduce boilerplate with annotations
✅ **Production ready** - Designed for real-world applications

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Application                        │
│              (Your Business Logic)                   │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│                OfflineStore                          │
│         (Public API - Simple & Clean)                │
└──┬──────────────┬──────────────┬────────────────────┘
   │              │               │
   │ Operations   │ Sync          │ Queries
   ▼              ▼               ▼
┌──────────┐  ┌──────────┐  ┌──────────────┐
│Operation │  │  Sync    │  │   Storage    │
│   Log    │  │  Engine  │  │   Adapter    │
└────┬─────┘  └────┬─────┘  └──────┬───────┘
     │             │                │
     │             │                │
     ▼             ▼                ▼
┌──────────┐  ┌──────────┐  ┌──────────────┐
│ Reducer  │  │ Remote   │  │ Local Storage│
│ (Squash) │  │ Adapter  │  │ (Hive/SQLite)│
└──────────┘  └────┬─────┘  └──────────────┘
                   │
                   ▼
            ┌──────────────┐
            │   Backend    │
            │ (REST/GraphQL│
            │   /gRPC)     │
            └──────────────┘
```

---

## Core Concepts

### 1. **Operation**

An operation represents a **domain intention**, not an HTTP request.

```dart
Operation(
  operationId: 'uuid-123',       // Unique ID for idempotency
  entityType: 'product',         // Entity type
  entityId: 'prod-456',          // Specific entity
  operationType: OperationType.update,
  payload: {'stock': 42},        // The change
  timestamp: 1234567890,         // Logical timestamp
  status: OperationStatus.pending,
  deviceId: 'device-789',
)
```

### 2. **Operation Log**

An append-only log of all operations, ordered by timestamp.

- Operations are **added**, never modified (except status)
- Can be **squashed** to optimize sync
- Ensures **causality** and **ordering**

### 3. **Sync Engine**

Responsible for:
- Processing pending operations in order
- Translating operations via remote adapters
- Handling retries and failures
- Conflict resolution
- Idempotency guarantees

### 4. **Remote Adapter**

Abstract interface for backend communication:

```dart
abstract class RemoteAdapter<T> {
  Future<SyncResult> create(Operation op);
  Future<SyncResult> update(Operation op);
  Future<SyncResult> delete(Operation op);
  Future<SyncResult> custom(Operation op);
}
```

**Adapters must ensure idempotency** using the `operationId`.

### 5. **Storage Adapter**

Abstract interface for local storage:

```dart
abstract class StorageAdapter {
  Future<void> saveEntity(String type, String id, Map data);
  Future<Map?> getEntity(String type, String id);
  Future<void> addOperation(Operation op);
  Future<List<Operation>> getPendingOperations();
  // ... more methods
}
```

Implementations: `InMemoryStorageAdapter` (included), or create your own for Hive, SQLite, etc.

---

## Operation Squashing

The **OperationReducer** optimizes operation queues before sync:

| Operations | Result |
|------------|--------|
| `CREATE` + `UPDATE` | `CREATE` (with merged payload) |
| `CREATE` + `DELETE` | ❌ Cancelled (never existed) |
| `UPDATE` + `UPDATE` | `UPDATE` (with merged payload) |
| `UPDATE` + `DELETE` | `DELETE` |

Example:

```
Before: [CREATE(name='A'), UPDATE(name='B'), UPDATE(price=10)]
After:  [CREATE(name='B', price=10)]
```

This reduces network traffic and sync time.

---

## Conflict Resolution

Pluggable conflict resolution strategies:

### Built-in Resolvers

1. **LastWriteWinsResolver** (default)
   - Compares timestamps
   - Most recent wins

2. **FieldLevelMergeResolver**
   - Merges non-conflicting field changes
   - Requires manual intervention for conflicts

### Custom Resolvers

Implement `ConflictResolver`:

```dart
class MyResolver extends ConflictResolver {
  @override
  Future<Resolution> resolve(
    LocalState local,
    RemoteState remote,
    List<Operation> pending,
  ) async {
    // Your logic here
    return Resolution.useLocal();
  }
}
```

---

## Usage

### 1. Define Your Entity

```dart
import 'package:offline_first/offline_first.dart';

part 'product.offline.g.dart';

@OfflineEntity(
  type: 'product',
  idField: 'id',
)
class Product {
  final String id;
  final String name;
  final double price;

  @OfflineIgnore()
  final DateTime? lastModified;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.lastModified,
  });
}
```

### 2. Generate Code

```bash
dart run build_runner build
```

This generates:
- `toMap()` / `fromMap()` methods
- Entity type constants
- Helper extensions

### 3. Implement Remote Adapter

```dart
class ProductRemoteAdapter extends RemoteAdapter<Product> {
  @override
  String get entityType => 'product';

  @override
  Future<SyncResult> create(Operation operation) async {
    // Check idempotency
    if (await backend.hasProcessed(operation.operationId)) {
      return SyncResult.success();
    }

    // Send to backend
    final response = await http.post(
      Uri.parse('https://api.example.com/products'),
      headers: {
        'X-Operation-Id': operation.operationId,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(operation.payload),
    );

    if (response.statusCode == 200) {
      return SyncResult.success();
    } else {
      return SyncResult.failure(
        errorMessage: response.body,
        isRetryable: response.statusCode >= 500,
      );
    }
  }

  @override
  Future<SyncResult> update(Operation operation) async {
    // Similar implementation
  }

  @override
  Future<SyncResult> delete(Operation operation) async {
    // Similar implementation
  }

  @override
  Future<Map<String, dynamic>?> fetchRemoteState(String entityId) async {
    final response = await http.get(
      Uri.parse('https://api.example.com/products/$entityId'),
    );
    return jsonDecode(response.body);
  }
}
```

### 4. Initialize Store

```dart
Future<void> main() async {
  // Initialize storage
  final storage = InMemoryStorageAdapter();
  // Or: final storage = HiveStorageAdapter();

  // Register adapters
  final adapters = {
    'product': ProductRemoteAdapter(),
  };

  // Create store
  final store = await OfflineStore.init(
    storage: storage,
    adapters: adapters,
    conflictResolver: LastWriteWinsResolver(),
    config: OfflineStoreConfig(
      deviceId: 'my-device-123',
      syncConfig: SyncConfig(
        enableOperationReduction: true,
        maxRetries: 3,
      ),
    ),
  );

  runApp(MyApp(store: store));
}
```

### 5. Use the Store

```dart
// Create
final product = Product(
  id: uuid.v4(),
  name: 'Laptop',
  price: 999.99,
);
await store.save('product', product.id, product.toMap(), isNew: true);

// Update
await store.save('product', product.id, {'price': 899.99});

// Delete
await store.delete('product', product.id);

// Query
final data = await store.get('product', product.id);
final allProducts = await store.getAll('product');

// Sync
await store.sync();

// Listen to sync status
store.syncStatusStream.listen((event) {
  print('Sync status: ${event.status}');
  print('Progress: ${event.progress}');
});

// Check pending operations
final pendingCount = await store.getPendingOperationsCount();
```

---

## Example App

A complete Flutter Web example is included in `/example/flutter_web_app`.

Features:
- ✅ Full CRUD operations
- ✅ Offline mode simulation
- ✅ Visual operation queue
- ✅ Real-time sync status
- ✅ Operation squashing demonstration
- ✅ Mock backend

Run the example:

```bash
cd example/flutter_web_app
flutter pub get
flutter run -d chrome
```

---

## Idempotency

**Idempotency is critical** for offline-first systems. This package ensures:

1. **Operation IDs**: Every operation has a unique UUID
2. **Adapter responsibility**: Adapters must check if an operation was already processed
3. **Backend support**: Your backend should accept `X-Operation-Id` headers and deduplicate

Example backend pseudocode:

```javascript
app.post('/api/products', async (req, res) => {
  const opId = req.headers['x-operation-id'];

  // Check if already processed
  if (await db.hasProcessedOperation(opId)) {
    return res.status(200).json({ status: 'already_processed' });
  }

  // Process operation
  await db.createProduct(req.body);
  await db.markOperationProcessed(opId);

  res.status(201).json({ status: 'created' });
});
```

---

## Sync Flow

```
┌─────────────┐
│  User Edit  │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Apply Locally   │ (Source of truth)
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ Add to Op Log   │
└──────┬──────────┘
       │
       │ (When online)
       ▼
┌─────────────────┐
│ Reduce Ops      │ (Optional squashing)
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ Sync Ops 1-by-1 │
└──────┬──────────┘
       │
       ├─ Success ──> Remove from log
       │
       ├─ Failure ──> Retry or mark failed
       │
       └─ Conflict ─> Resolve ──> Retry or apply
```

---

## Testing

Run tests:

```bash
dart test
```

Key test scenarios:
- ✅ Operation creation and serialization
- ✅ Operation log management
- ✅ Operation squashing logic
- ✅ Sync engine behavior
- ✅ Conflict resolution
- ✅ Storage adapter contracts

---

## Design Decisions

### Why Operation-Log?

- **Causality**: Operations have ordering
- **Auditability**: Full history of changes
- **Optimizability**: Can be squashed/reduced
- **Resilience**: Survives crashes and retries

### Why Not Snapshots?

- Snapshots send entire entity state
- Wasteful for small changes
- Harder to optimize
- Loses change semantics

### Why Abstract Storage?

- Different projects use different storage (Hive, SQLite, IndexedDB)
- Keeps package agnostic and reusable
- Easy to test with in-memory adapter

### Why Abstract Remote Adapter?

- Backends vary (REST, GraphQL, gRPC, WebSocket)
- HTTP is not a hard dependency
- Allows custom protocols and authentication

---

## Production Considerations

1. **Connection detection**: This package does NOT detect online/offline state. Use `connectivity_plus` or similar.

2. **Storage implementation**: Use a persistent storage adapter (Hive, SQLite) in production, not `InMemoryStorageAdapter`.

3. **Backend idempotency**: Ensure your backend supports idempotent operations.

4. **Conflict handling**: Choose appropriate conflict resolution for your domain.

5. **Operation cleanup**: Periodically clean up old synced operations.

6. **Error monitoring**: Log sync failures for debugging.

7. **Security**: Secure your operations (encryption, authentication).

---

## Roadmap

- [ ] Built-in Hive storage adapter
- [ ] Built-in SQLite storage adapter
- [ ] Batch sync optimization
- [ ] Automatic retry with exponential backoff
- [ ] Operation expiration/TTL
- [ ] Compression for large payloads
- [ ] Encrypted storage support

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

---

## License

MIT License - see LICENSE file for details

---

## Credits

Inspired by:
- CouchDB replication protocol
- Firebase Firestore offline persistence
- Martin Kleppmann's work on CRDTs and local-first software

---

## Questions?

Open an issue on GitHub or check the example app for implementation details.

**Happy coding! 🚀**
