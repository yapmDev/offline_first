# Usage Modes Guide

The `offline_first` package supports two distinct usage patterns depending on whether you have existing storage infrastructure or are starting fresh.

---

## 🎯 Mode 1: Operation Logging Only (Recommended for Existing Apps)

**Use this mode when:**
- You have existing storage (Hive, SQLite, Isar, etc.)
- You want to add offline-first sync to an existing app
- You want clear separation of concerns
- **This is the recommended approach for most real-world apps**

### How It Works

Your app remains in full control of entity storage. OfflineStore ONLY manages the operation log for synchronization.

```dart
// 1. Your app saves to its own storage
await tagBox.put(tagId, tagModel);

// 2. Then logs the operation for sync
await offlineStore.logCreate('tag', tagId, tagData);
```

### Architecture

```
┌──────────────────────────────────────────┐
│          Your Application                │
│                                          │
│  ┌────────────┐      ┌────────────────┐ │
│  │ Repository │      │   Hive/SQLite  │ │
│  │            │─────>│                │ │
│  │            │      │  (Entities)    │ │
│  └─────┬──────┘      └────────────────┘ │
│        │                                 │
│        │ logCreate/Update/Delete         │
│        ▼                                 │
│  ┌────────────────────────────────────┐ │
│  │        OfflineStore                │ │
│  │   (Operation Log ONLY)             │ │
│  └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

### Full Example

```dart
@LazySingleton(as: TagRepository)
class TagRepositoryImpl implements TagRepository {
  final Box<TagModel> _tagBox;  // Your existing Hive storage
  final OfflineStore _offlineStore;
  final TagMapper _mapper;

  TagRepositoryImpl(this._tagBox, this._offlineStore, this._mapper);

  @override
  Future<void> create(String name, int color) async {
    final id = const Uuid().v4();
    final tag = TagModel(id: id, name: name, color: color);

    // 1. Save to YOUR storage (source of truth)
    await _tagBox.put(id, tag);

    // 2. Log operation for sync (ONLY logging, no storage)
    await _offlineStore.logCreate('tag', id, tag.toJson());
  }

  @override
  Future<void> update(Tag tag) async {
    final model = _mapper.toModel(tag);

    // 1. Update in YOUR storage
    await _tagBox.put(tag.id, model);

    // 2. Log operation for sync
    await _offlineStore.logUpdate('tag', tag.id, model.toJson());
  }

  @override
  Future<void> delete(String id) async {
    // 1. Delete from YOUR storage
    await _tagBox.delete(id);

    // 2. Log operation for sync
    await _offlineStore.logDelete('tag', id);
  }

  @override
  List<Tag> findAll() {
    // Read from YOUR storage, NOT from OfflineStore
    return _tagBox.values.map((m) => _mapper.toEntity(m)).toList();
  }

  @override
  Tag findById(String id) {
    final model = _tagBox.get(id);
    if (model == null) {
      throw NotFoundException('Tag not found: $id');
    }
    return _mapper.toEntity(model);
  }
}
```

### StorageAdapter Setup (Operation Log Only)

Since you're not using OfflineStore for entity storage, StorageAdapter only needs to handle operations and metadata:

```dart
@singleton
class HiveStorageAdapter implements StorageAdapter {
  Box<Map>? _operationsBox;
  Box? _metadataBox;

  @override
  Future<void> initialize() async {
    _operationsBox = await Hive.openBox<Map>('operations');
    _metadataBox = await Hive.openBox('syncMetadata');
  }

  // ========== Operation Log Operations ==========

  @override
  Future<void> addOperation(Operation operation) async {
    await _operationsBox!.put(operation.operationId, operation.toMap());
  }

  @override
  Future<List<Operation>> getPendingOperations() async {
    return _operationsBox!.values
        .map((data) => Operation.fromMap(Map<String, dynamic>.from(data)))
        .where((op) => op.status == OperationStatus.pending)
        .toList();
  }

  // ... other operation log methods

  // ========== Metadata Operations ==========

  @override
  Future<void> saveMetadata(String key, dynamic value) async {
    await _metadataBox!.put(key, value);
  }

  @override
  Future<dynamic> getMetadata(String key) async {
    return _metadataBox!.get(key);
  }

  // ========== Entity Operations (NOT USED in this mode) ==========

  @override
  Future<void> saveEntity(String entityType, String entityId, Map<String, dynamic> data) async {
    throw UnsupportedError('Use app storage directly, not OfflineStore');
  }

  @override
  Future<Map<String, dynamic>?> getEntity(String entityType, String entityId) async {
    throw UnsupportedError('Use app storage directly, not OfflineStore');
  }

  // ... other entity methods throw UnsupportedError
}
```

### API Reference (Operation Logging Mode)

| Method | Description |
|--------|-------------|
| `logCreate(entityType, entityId, payload)` | Log a CREATE operation without saving entity |
| `logUpdate(entityType, entityId, payload)` | Log an UPDATE operation without saving entity |
| `logDelete(entityType, entityId)` | Log a DELETE operation without deleting entity |
| `logCustom(entityType, entityId, name, payload)` | Log a custom operation |
| `sync()` | Synchronize all pending operations with remote |
| `getPendingOperationsCount()` | Get count of operations waiting for sync |
| `syncStatusStream` | Listen to sync progress events |

---

## 🚀 Mode 2: OfflineStore as Source of Truth (New Apps)

**Use this mode when:**
- Building a new app from scratch
- You don't have existing storage infrastructure
- You want OfflineStore to handle everything
- Simplicity is more important than separation of concerns

### How It Works

OfflineStore manages BOTH entity storage and operation logging.

```dart
// OfflineStore handles both storage and logging
await offlineStore.save('tag', tagId, tagData, isNew: true);
final tag = await offlineStore.get('tag', tagId);
final tags = await offlineStore.getAll('tag');
await offlineStore.delete('tag', tagId);
```

### Architecture

```
┌──────────────────────────────────────────┐
│          Your Application                │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │        OfflineStore                │ │
│  │  (Entities + Operations)           │ │
│  │                                    │ │
│  │  ┌──────────┐    ┌──────────────┐ │ │
│  │  │ Entities │    │  Operations  │ │ │
│  │  │  (via    │    │     Log      │ │ │
│  │  │ Storage) │    │              │ │ │
│  │  └──────────┘    └──────────────┘ │ │
│  └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

### Full Example

```dart
@LazySingleton(as: TagRepository)
class TagRepositoryOfflineStore implements TagRepository {
  final OfflineStore _offlineStore;

  TagRepositoryOfflineStore(this._offlineStore);

  @override
  Future<void> create(String name, int color) async {
    final id = const Uuid().v4();
    final data = {
      'id': id,
      'name': name,
      'color': color,
    };

    // OfflineStore handles both storage and logging
    await _offlineStore.save('tag', id, data, isNew: true);
  }

  @override
  Future<void> update(Tag tag) async {
    final data = {
      'id': tag.id,
      'name': tag.name,
      'color': tag.color,
    };

    // OfflineStore determines if it's update or create
    await _offlineStore.save('tag', tag.id, data);
  }

  @override
  Future<void> delete(String id) async {
    await _offlineStore.delete('tag', id);
  }

  @override
  Future<List<Tag>> findAll() async {
    final tagsData = await _offlineStore.getAll('tag');
    return tagsData.map((data) => Tag.fromMap(data)).toList();
  }

  @override
  Future<Tag?> findById(String id) async {
    final data = await _offlineStore.get('tag', id);
    return data != null ? Tag.fromMap(data) : null;
  }
}
```

### StorageAdapter Setup (Full Storage)

StorageAdapter must implement entity storage methods:

```dart
@singleton
class HiveStorageAdapter implements StorageAdapter {
  final Map<String, Box<Map>> _entityBoxes = {};
  Box<Map>? _operationsBox;
  Box? _metadataBox;

  @override
  Future<void> initialize() async {
    _operationsBox = await Hive.openBox<Map>('operations');
    _metadataBox = await Hive.openBox('syncMetadata');
  }

  Future<Box<Map>> _getEntityBox(String entityType) async {
    if (!_entityBoxes.containsKey(entityType)) {
      _entityBoxes[entityType] = await Hive.openBox<Map>('entities_$entityType');
    }
    return _entityBoxes[entityType]!;
  }

  // ========== Entity Operations ==========

  @override
  Future<void> saveEntity(String entityType, String entityId, Map<String, dynamic> data) async {
    final box = await _getEntityBox(entityType);
    await box.put(entityId, data);
  }

  @override
  Future<Map<String, dynamic>?> getEntity(String entityType, String entityId) async {
    final box = await _getEntityBox(entityType);
    final data = box.get(entityId);
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllEntities(String entityType) async {
    final box = await _getEntityBox(entityType);
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<void> deleteEntity(String entityType, String entityId) async {
    final box = await _getEntityBox(entityType);
    await box.delete(entityId);
  }

  // ... operation log methods
  // ... metadata methods
}
```

### API Reference (Source of Truth Mode)

| Method | Description |
|--------|-------------|
| `save(entityType, entityId, data, {isNew})` | Save entity to storage + log operation |
| `delete(entityType, entityId)` | Delete entity from storage + log operation |
| `get(entityType, entityId)` | Read entity from storage |
| `getAll(entityType)` | Read all entities of type from storage |
| `sync()` | Synchronize all pending operations with remote |
| `getPendingOperationsCount()` | Get count of operations waiting for sync |
| `syncStatusStream` | Listen to sync progress events |

---

## 📊 Comparison

| Aspect | Operation Logging Mode | Source of Truth Mode |
|--------|------------------------|----------------------|
| **Entity Storage** | App manages (Hive/SQLite) | OfflineStore manages |
| **Operation Logging** | OfflineStore | OfflineStore |
| **Separation of Concerns** | ✅ High | ❌ Coupled |
| **Existing App Integration** | ✅ Easy | ❌ Requires migration |
| **Repository Pattern** | ✅ Preserved | Changes required |
| **Complexity** | Medium | Low |
| **Recommended For** | Production apps | Prototypes/New apps |

---

## 🔄 Sync Process (Same for Both Modes)

Regardless of which mode you use, synchronization works identically:

```dart
// Manual sync
await offlineStore.sync();

// Listen to sync status
offlineStore.syncStatusStream.listen((event) {
  if (event.status == SyncStatus.syncing) {
    print('Syncing ${event.operation?.entityType}...');
  } else if (event.status == SyncStatus.error) {
    print('Sync error: ${event.errorMessage}');
  } else if (event.status == SyncStatus.idle) {
    print('Sync complete!');
  }
});

// Auto-sync on connectivity
connectivity.onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) {
    offlineStore.sync();
  }
});
```

---

## 🎯 Recommendation

**For most real-world applications, use Operation Logging Mode.**

It provides better separation of concerns, easier integration with existing code, and aligns with the principle that your app should own its data storage strategy.

Use Source of Truth Mode only for:
- New greenfield projects
- Prototypes and demos
- Apps where simplicity trumps architecture
