import '../core/operation.dart';
import '../core/conflict_resolution.dart';
import 'conflict_resolver.dart';

/// Field-level merge conflict resolution strategy
/// Attempts to merge non-conflicting field changes
class FieldLevelMergeResolver extends ConflictResolver {
  @override
  Future<Resolution> resolve(
    LocalState local,
    RemoteState remote,
    List<Operation> pendingOperations,
  ) async {
    final merged = <String, dynamic>{...remote.data};
    final conflicts = <String>[];

    // Get fields that were modified locally
    final localChanges = _getModifiedFields(pendingOperations);

    for (final field in localChanges.keys) {
      final localValue = local.data[field];

      // If remote doesn't have this field, no conflict - use local value
      if (!remote.data.containsKey(field)) {
        merged[field] = localValue;
      } else {
        final remoteValue = remote.data[field];

        // If remote has the same value, no conflict
        if (remoteValue == localValue) {
          merged[field] = localValue;
        } else {
          // Both modified the same field to different values - conflict
          conflicts.add(field);
        }
      }
    }

    if (conflicts.isEmpty) {
      // Successful merge
      return Resolution.merge(merged);
    } else {
      // Has conflicts, require manual intervention
      return Resolution.manual();
    }
  }

  /// Extract modified fields from pending operations
  Map<String, dynamic> _getModifiedFields(List<Operation> operations) {
    final modified = <String, dynamic>{};
    for (final op in operations) {
      if (op.operationType == OperationType.update ||
          op.operationType == OperationType.create) {
        modified.addAll(op.payload);
      }
    }
    return modified;
  }
}
