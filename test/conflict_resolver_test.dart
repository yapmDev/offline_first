import 'package:test/test.dart';
import 'package:offline_first/offline_first.dart';

void main() {
  group('LastWriteWinsResolver', () {
    late LastWriteWinsResolver resolver;

    setUp(() {
      resolver = LastWriteWinsResolver();
    });

    test('should choose local when local is newer', () async {
      final local = const LocalState(
        data: {'name': 'Local'},
        timestamp: 2000,
      );

      final remote = const RemoteState(
        data: {'name': 'Remote'},
        timestamp: 1000,
      );

      final resolution = await resolver.resolve(local, remote, []);

      expect(resolution.strategy, ResolutionStrategy.useLocal);
    });

    test('should choose remote when remote is newer', () async {
      final local = const LocalState(
        data: {'name': 'Local'},
        timestamp: 1000,
      );

      final remote = const RemoteState(
        data: {'name': 'Remote'},
        timestamp: 2000,
      );

      final resolution = await resolver.resolve(local, remote, []);

      expect(resolution.strategy, ResolutionStrategy.useRemote);
    });

    test('should choose local when timestamps are equal', () async {
      final local = const LocalState(
        data: {'name': 'Local'},
        timestamp: 1000,
      );

      final remote = const RemoteState(
        data: {'name': 'Remote'},
        timestamp: 1000,
      );

      final resolution = await resolver.resolve(local, remote, []);

      expect(resolution.strategy, ResolutionStrategy.useLocal);
    });
  });

  group('FieldLevelMergeResolver', () {
    late FieldLevelMergeResolver resolver;

    setUp(() {
      resolver = FieldLevelMergeResolver();
    });

    test('should merge non-conflicting fields', () async {
      final local = const LocalState(
        data: {'name': 'Local', 'price': 10.0},
        timestamp: 1000,
      );

      final remote = const RemoteState(
        data: {'name': 'Remote', 'stock': 100},
        timestamp: 2000,
      );

      final pendingOps = [
        const Operation(
          operationId: 'op-1',
          entityType: 'product',
          entityId: 'prod-1',
          operationType: OperationType.update,
          payload: {'price': 10.0},
          timestamp: 1000,
          status: OperationStatus.pending,
          deviceId: 'device-1',
        ),
      ];

      final resolution = await resolver.resolve(local, remote, pendingOps);

      expect(resolution.strategy, ResolutionStrategy.merge);
      expect(resolution.mergedData, isNotNull);
      expect(resolution.mergedData!['price'], 10.0);
      expect(resolution.mergedData!['stock'], 100);
    });
  });
}
