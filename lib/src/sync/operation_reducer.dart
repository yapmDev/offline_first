import '../core/operation.dart';

/// Result of attempting to reduce/squash operations
class ReduceResult {
  /// The reduced operation (or null if operations cancel out)
  final Operation? reducedOperation;

  /// Whether the operations were successfully reduced
  final bool wasReduced;

  const ReduceResult({
    this.reducedOperation,
    required this.wasReduced,
  });

  factory ReduceResult.reduced(Operation operation) {
    return ReduceResult(
      reducedOperation: operation,
      wasReduced: true,
    );
  }

  factory ReduceResult.cancelled() {
    return const ReduceResult(
      reducedOperation: null,
      wasReduced: true,
    );
  }

  factory ReduceResult.notReduced() {
    return const ReduceResult(
      reducedOperation: null,
      wasReduced: false,
    );
  }
}

/// Reduces/squashes operations to optimize sync
abstract class OperationReducer {
  /// Try to reduce two consecutive operations on the same entity
  /// Returns null if they cancel out, or a new reduced operation
  ReduceResult reduce(Operation first, Operation second);

  /// Try to reduce a list of operations for the same entity
  /// Returns a list of reduced operations (may be empty if all cancel out)
  List<Operation> reduceMany(List<Operation> operations) {
    if (operations.length <= 1) return operations;

    final reduced = <Operation>[];
    Operation? current = operations.first;

    for (int i = 1; i < operations.length; i++) {
      final next = operations[i];

      if (current == null) {
        current = next;
        continue;
      }

      final result = reduce(current, next);

      if (result.wasReduced) {
        current = result.reducedOperation;
      } else {
        reduced.add(current);
        current = next;
      }
    }

    if (current != null) {
      reduced.add(current);
    }

    return reduced;
  }
}

/// Default implementation with standard reduction rules:
/// - CREATE + UPDATE → CREATE (with merged payload)
/// - CREATE + DELETE → cancelled
/// - UPDATE + UPDATE → UPDATE (with merged payload)
/// - UPDATE + DELETE → DELETE
class DefaultOperationReducer extends OperationReducer {
  @override
  ReduceResult reduce(Operation first, Operation second) {
    // Can only reduce operations on the same entity
    if (first.entityType != second.entityType || first.entityId != second.entityId) {
      return ReduceResult.notReduced();
    }

    // CREATE + UPDATE → CREATE (with updated payload)
    if (first.operationType == OperationType.create &&
        second.operationType == OperationType.update) {
      return ReduceResult.reduced(
        first.copyWith(
          payload: {...first.payload, ...second.payload},
          timestamp: second.timestamp,
        ),
      );
    }

    // CREATE + DELETE → cancelled (entity never existed on server)
    if (first.operationType == OperationType.create &&
        second.operationType == OperationType.delete) {
      return ReduceResult.cancelled();
    }

    // UPDATE + UPDATE → UPDATE (merge payloads)
    if (first.operationType == OperationType.update &&
        second.operationType == OperationType.update) {
      return ReduceResult.reduced(
        first.copyWith(
          payload: {...first.payload, ...second.payload},
          timestamp: second.timestamp,
        ),
      );
    }

    // UPDATE + DELETE → DELETE
    if (first.operationType == OperationType.update &&
        second.operationType == OperationType.delete) {
      return ReduceResult.reduced(second);
    }

    // No reduction possible
    return ReduceResult.notReduced();
  }
}
