import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

void main() {
  group('Operation', () {
    test('should create operation with required fields', () {
      final operation = Operation(
        operationId: 'op-123',
        entityType: 'product',
        entityId: 'prod-456',
        operationType: OperationType.create,
        payload: {'name': 'Test'},
        timestamp: 1234567890,
        status: OperationStatus.pending,
        deviceId: 'device-789',
      );

      expect(operation.operationId, 'op-123');
      expect(operation.entityType, 'product');
      expect(operation.operationType, OperationType.create);
      expect(operation.status, OperationStatus.pending);
    });

    test('should serialize to map', () {
      final operation = Operation(
        operationId: 'op-123',
        entityType: 'product',
        entityId: 'prod-456',
        operationType: OperationType.update,
        payload: {'name': 'Test'},
        timestamp: 1234567890,
        status: OperationStatus.pending,
        deviceId: 'device-789',
      );

      final map = operation.toMap();

      expect(map['operationId'], 'op-123');
      expect(map['entityType'], 'product');
      expect(map['operationType'], 'update');
      expect(map['status'], 'pending');
    });

    test('should deserialize from map', () {
      final map = {
        'operationId': 'op-123',
        'entityType': 'product',
        'entityId': 'prod-456',
        'operationType': 'create',
        'payload': {'name': 'Test'},
        'timestamp': 1234567890,
        'status': 'pending',
        'deviceId': 'device-789',
        'retryCount': 0,
      };

      final operation = Operation.fromMap(map);

      expect(operation.operationId, 'op-123');
      expect(operation.entityType, 'product');
      expect(operation.operationType, OperationType.create);
      expect(operation.status, OperationStatus.pending);
    });

    test('should copy with modified fields', () {
      final operation = Operation(
        operationId: 'op-123',
        entityType: 'product',
        entityId: 'prod-456',
        operationType: OperationType.create,
        payload: {'name': 'Test'},
        timestamp: 1234567890,
        status: OperationStatus.pending,
        deviceId: 'device-789',
      );

      final updated = operation.copyWith(
        status: OperationStatus.synced,
        retryCount: 3,
      );

      expect(updated.operationId, operation.operationId);
      expect(updated.status, OperationStatus.synced);
      expect(updated.retryCount, 3);
    });
  });
}
