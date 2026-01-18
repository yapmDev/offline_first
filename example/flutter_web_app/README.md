# Offline First Demo - Flutter Web Example

This is a complete demonstration of the `offline_first` package showing all key features in action.

## Features Demonstrated

✅ **CRUD Operations** - Create, read, update, delete products
✅ **Offline Mode** - Toggle online/offline to simulate network conditions
✅ **Operation Queue** - Visual display of pending operations
✅ **Sync Status** - Real-time sync progress and status
✅ **Operation Squashing** - Multiple operations on same entity are optimized
✅ **Idempotency** - Operations are safely retried without duplication
✅ **Mock Backend** - In-memory backend simulating real server

## Running the Example

```bash
cd example/flutter_web_app
flutter pub get
flutter run -d chrome
```

## How to Use

1. **Add Products** - Click the + button to create new products
2. **Edit Products** - Click the edit icon to modify a product
3. **Delete Products** - Click the delete icon to remove a product
4. **Go Offline** - Click the cloud icon to simulate offline mode
5. **Make Changes Offline** - Create/edit/delete while offline
6. **View Operations** - Check the right panel for pending operations
7. **Sync** - Click the sync button to synchronize with backend
8. **Observe Squashing** - Make multiple edits to the same product and watch them merge

## Architecture

```
┌──────────────┐
│   Flutter UI │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ OfflineStore │ (API)
└──────┬───────┘
       │
       ├─────────────┐
       │             │
       ▼             ▼
┌──────────┐  ┌──────────────┐
│   Sync   │  │   Storage    │
│  Engine  │  │   (Memory)   │
└────┬─────┘  └──────────────┘
     │
     ▼
┌──────────────────┐
│ ProductAdapter   │
└────┬─────────────┘
     │
     ▼
┌──────────────────┐
│  Mock Backend    │
└──────────────────┘
```

## Key Files

- `lib/main.dart` - Main UI with product list and operation queue
- `lib/models/product.dart` - Product entity with @OfflineEntity annotation
- `lib/adapters/product_remote_adapter.dart` - Remote adapter implementation
- `lib/backend/mock_backend.dart` - Mock backend server

## Learning Points

### 1. Entity Definition

```dart
@OfflineEntity(type: 'product', idField: 'id')
class Product {
  final String id;
  final String name;
  final double price;
  final int stock;
}
```

### 2. Remote Adapter

The adapter translates operations into backend calls and ensures idempotency:

```dart
@override
Future<SyncResult> create(Operation operation) async {
  // Check if already processed
  if (backend.hasProcessedOperation(operation.operationId)) {
    return SyncResult.success();
  }

  // Process operation
  await backend.createProduct(product);
  backend.markOperationProcessed(operation.operationId);

  return SyncResult.success();
}
```

### 3. Store Usage

```dart
// Create
await store.save('product', product.id, product.toMap(), isNew: true);

// Update
await store.save('product', product.id, product.toMap());

// Delete
await store.delete('product', product.id);

// Sync
await store.sync();
```

## Experiment!

Try these scenarios:

1. **Create → Update → Sync** - Create a product, edit it multiple times offline, then sync. Notice how operations are squashed.

2. **Create → Delete → Sync** - Create a product, delete it offline, then sync. The operations cancel out!

3. **Multiple Products** - Create many products offline and sync them all at once.

4. **Failed Sync** - Go offline, make changes, try to sync (it will fail), go online, sync again.

## Next Steps

After exploring this example:

1. Implement your own entity types
2. Create real HTTP-based adapters
3. Use persistent storage (Hive, SQLite)
4. Add authentication to your adapters
5. Implement custom conflict resolution

Enjoy exploring offline-first architecture! 🚀
