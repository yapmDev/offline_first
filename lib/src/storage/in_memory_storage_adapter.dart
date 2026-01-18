import '../core/operation.dart';
import 'storage_adapter.dart';

/// In-memory implementation of StorageAdapter for testing and examples
class InMemoryStorageAdapter implements StorageAdapter {
  final Map<String, Map<String, Map<String, dynamic>>> _entities = {};
  final Map<String, Operation> _operations = {};
  final Map<String, dynamic> _metadata = {};
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('StorageAdapter not initialized. Call initialize() first.');
    }
  }

  // ============ Entity Operations ============

  @override
  Future<void> saveEntity(String entityType, String entityId, Map<String, dynamic> data) async {
    _ensureInitialized();
    _entities.putIfAbsent(entityType, () => {});
    _entities[entityType]![entityId] = Map<String, dynamic>.from(data);
  }

  @override
  Future<Map<String, dynamic>?> getEntity(String entityType, String entityId) async {
    _ensureInitialized();
    final typeEntities = _entities[entityType];
    if (typeEntities == null) return null;
    final entity = typeEntities[entityId];
    return entity != null ? Map<String, dynamic>.from(entity) : null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllEntities(String entityType) async {
    _ensureInitialized();
    final typeEntities = _entities[entityType];
    if (typeEntities == null) return [];
    return typeEntities.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> deleteEntity(String entityType, String entityId) async {
    _ensureInitialized();
    _entities[entityType]?.remove(entityId);
  }

  @override
  Future<bool> entityExists(String entityType, String entityId) async {
    _ensureInitialized();
    return _entities[entityType]?.containsKey(entityId) ?? false;
  }

  // ============ Operation Log Operations ============

  @override
  Future<void> addOperation(Operation operation) async {
    _ensureInitialized();
    _operations[operation.operationId] = operation;
  }

  @override
  Future<Operation?> getOperation(String operationId) async {
    _ensureInitialized();
    return _operations[operationId];
  }

  @override
  Future<List<Operation>> getPendingOperations() async {
    _ensureInitialized();
    final pending = _operations.values
        .where((op) => op.status == OperationStatus.pending)
        .toList();
    pending.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return pending;
  }

  @override
  Future<List<Operation>> getOperationsForEntity(String entityType, String entityId) async {
    _ensureInitialized();
    return _operations.values
        .where((op) => op.entityType == entityType && op.entityId == entityId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<void> updateOperation(Operation operation) async {
    _ensureInitialized();
    _operations[operation.operationId] = operation;
  }

  @override
  Future<void> deleteOperation(String operationId) async {
    _ensureInitialized();
    _operations.remove(operationId);
  }

  @override
  Future<void> deleteOperations(List<String> operationIds) async {
    _ensureInitialized();
    for (final id in operationIds) {
      _operations.remove(id);
    }
  }

  @override
  Future<int> getPendingOperationsCount() async {
    _ensureInitialized();
    return _operations.values
        .where((op) => op.status == OperationStatus.pending)
        .length;
  }

  // ============ Metadata Operations ============

  @override
  Future<void> saveMetadata(String key, dynamic value) async {
    _ensureInitialized();
    _metadata[key] = value;
  }

  @override
  Future<dynamic> getMetadata(String key) async {
    _ensureInitialized();
    return _metadata[key];
  }

  @override
  Future<void> clearMetadata() async {
    _ensureInitialized();
    _metadata.clear();
  }

  // ============ Batch Operations ============

  @override
  Future<bool> executeTransaction(Future<void> Function(StorageAdapter adapter) operations) async {
    _ensureInitialized();
    try {
      await operations(this);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clearAll() async {
    _entities.clear();
    _operations.clear();
    _metadata.clear();
  }
}
