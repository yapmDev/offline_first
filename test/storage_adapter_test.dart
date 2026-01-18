import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

void main() {
  group('InMemoryStorageAdapter', () {
    late InMemoryStorageAdapter storage;

    setUp(() async {
      storage = InMemoryStorageAdapter();
      await storage.initialize();
    });

    tearDown(() async {
      await storage.close();
    });

    test('should save and retrieve entity', () async {
      await storage.saveEntity('product', 'prod-1', {'name': 'Test'});

      final entity = await storage.getEntity('product', 'prod-1');

      expect(entity, isNotNull);
      expect(entity!['name'], 'Test');
    });

    test('should return null for non-existent entity', () async {
      final entity = await storage.getEntity('product', 'non-existent');

      expect(entity, isNull);
    });

    test('should delete entity', () async {
      await storage.saveEntity('product', 'prod-1', {'name': 'Test'});
      await storage.deleteEntity('product', 'prod-1');

      final entity = await storage.getEntity('product', 'prod-1');

      expect(entity, isNull);
    });

    test('should check entity existence', () async {
      await storage.saveEntity('product', 'prod-1', {'name': 'Test'});

      expect(await storage.entityExists('product', 'prod-1'), true);
      expect(await storage.entityExists('product', 'non-existent'), false);
    });

    test('should get all entities of a type', () async {
      await storage.saveEntity('product', 'prod-1', {'name': 'A'});
      await storage.saveEntity('product', 'prod-2', {'name': 'B'});
      await storage.saveEntity('user', 'user-1', {'name': 'C'});

      final products = await storage.getAllEntities('product');

      expect(products.length, 2);
    });

    test('should add and retrieve operation', () async {
      final operation = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.create,
        payload: {'name': 'Test'},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      await storage.addOperation(operation);

      final retrieved = await storage.getOperation('op-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.operationId, 'op-1');
    });

    test('should get pending operations in order', () async {
      final op1 = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.create,
        payload: {},
        timestamp: 2000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final op2 = Operation(
        operationId: 'op-2',
        entityType: 'product',
        entityId: 'prod-2',
        operationType: OperationType.create,
        payload: {},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final op3 = Operation(
        operationId: 'op-3',
        entityType: 'product',
        entityId: 'prod-3',
        operationType: OperationType.create,
        payload: {},
        timestamp: 3000,
        status: OperationStatus.synced,
        deviceId: 'device-1',
      );

      await storage.addOperation(op1);
      await storage.addOperation(op2);
      await storage.addOperation(op3);

      final pending = await storage.getPendingOperations();

      expect(pending.length, 2);
      expect(pending[0].operationId, 'op-2'); // timestamp 1000
      expect(pending[1].operationId, 'op-1'); // timestamp 2000
    });

    test('should update operation', () async {
      final operation = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.create,
        payload: {},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      await storage.addOperation(operation);

      final updated = operation.copyWith(status: OperationStatus.synced);
      await storage.updateOperation(updated);

      final retrieved = await storage.getOperation('op-1');

      expect(retrieved!.status, OperationStatus.synced);
    });

    test('should delete operation', () async {
      final operation = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.create,
        payload: {},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      await storage.addOperation(operation);
      await storage.deleteOperation('op-1');

      final retrieved = await storage.getOperation('op-1');

      expect(retrieved, isNull);
    });

    test('should save and retrieve metadata', () async {
      await storage.saveMetadata('lastSync', 12345);

      final value = await storage.getMetadata('lastSync');

      expect(value, 12345);
    });

    test('should execute transaction', () async {
      final success = await storage.executeTransaction((adapter) async {
        await adapter.saveEntity('product', 'prod-1', {'name': 'A'});
        await adapter.saveEntity('product', 'prod-2', {'name': 'B'});
      });

      expect(success, true);

      final products = await storage.getAllEntities('product');
      expect(products.length, 2);
    });
  });
}
