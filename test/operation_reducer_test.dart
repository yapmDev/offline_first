import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

void main() {
  group('DefaultOperationReducer', () {
    late DefaultOperationReducer reducer;

    setUp(() {
      reducer = DefaultOperationReducer();
    });

    test('CREATE + UPDATE should merge into CREATE', () {
      final create = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.create,
        payload: {'name': 'A', 'price': 10.0},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final update = Operation(
        operationId: 'op-2',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.update,
        payload: {'name': 'B'},
        timestamp: 2000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final result = reducer.reduce(create, update);

      expect(result.wasReduced, true);
      expect(result.reducedOperation?.operationType, OperationType.create);
      expect(result.reducedOperation?.payload['name'], 'B');
      expect(result.reducedOperation?.payload['price'], 10.0);
    });

    test('CREATE + DELETE should cancel', () {
      final create = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.create,
        payload: {'name': 'A'},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final delete = Operation(
        operationId: 'op-2',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.delete,
        payload: {},
        timestamp: 2000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final result = reducer.reduce(create, delete);

      expect(result.wasReduced, true);
      expect(result.reducedOperation, null);
    });

    test('UPDATE + UPDATE should merge into UPDATE', () {
      final update1 = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.update,
        payload: {'name': 'A'},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final update2 = Operation(
        operationId: 'op-2',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.update,
        payload: {'price': 20.0},
        timestamp: 2000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final result = reducer.reduce(update1, update2);

      expect(result.wasReduced, true);
      expect(result.reducedOperation?.operationType, OperationType.update);
      expect(result.reducedOperation?.payload['name'], 'A');
      expect(result.reducedOperation?.payload['price'], 20.0);
    });

    test('UPDATE + DELETE should become DELETE', () {
      final update = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.update,
        payload: {'name': 'A'},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final delete = Operation(
        operationId: 'op-2',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.delete,
        payload: {},
        timestamp: 2000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final result = reducer.reduce(update, delete);

      expect(result.wasReduced, true);
      expect(result.reducedOperation?.operationType, OperationType.delete);
    });

    test('operations on different entities should not reduce', () {
      final op1 = Operation(
        operationId: 'op-1',
        entityType: 'product',
        entityId: 'prod-1',
        operationType: OperationType.create,
        payload: {'name': 'A'},
        timestamp: 1000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final op2 = Operation(
        operationId: 'op-2',
        entityType: 'product',
        entityId: 'prod-2',
        operationType: OperationType.create,
        payload: {'name': 'B'},
        timestamp: 2000,
        status: OperationStatus.pending,
        deviceId: 'device-1',
      );

      final result = reducer.reduce(op1, op2);

      expect(result.wasReduced, false);
    });

    test('reduceMany should handle multiple operations', () {
      final ops = [
        Operation(
          operationId: 'op-1',
          entityType: 'product',
          entityId: 'prod-1',
          operationType: OperationType.create,
          payload: {'name': 'A', 'price': 10.0},
          timestamp: 1000,
          status: OperationStatus.pending,
          deviceId: 'device-1',
        ),
        Operation(
          operationId: 'op-2',
          entityType: 'product',
          entityId: 'prod-1',
          operationType: OperationType.update,
          payload: {'name': 'B'},
          timestamp: 2000,
          status: OperationStatus.pending,
          deviceId: 'device-1',
        ),
        Operation(
          operationId: 'op-3',
          entityType: 'product',
          entityId: 'prod-1',
          operationType: OperationType.update,
          payload: {'stock': 100},
          timestamp: 3000,
          status: OperationStatus.pending,
          deviceId: 'device-1',
        ),
      ];

      final reduced = reducer.reduceMany(ops);

      expect(reduced.length, 1);
      expect(reduced[0].operationType, OperationType.create);
      expect(reduced[0].payload['name'], 'B');
      expect(reduced[0].payload['price'], 10.0);
      expect(reduced[0].payload['stock'], 100);
    });
  });
}
