import '../core/operation.dart';
import '../core/conflict_resolution.dart';

/// Abstract conflict resolver for pluggable conflict resolution strategies
abstract class ConflictResolver {
  /// Resolve a conflict between local and remote state
  ///
  /// [local] - The current local state
  /// [remote] - The conflicting remote state
  /// [pendingOperations] - List of pending operations for this entity
  ///
  /// Returns a Resolution indicating how to resolve the conflict
  Future<Resolution> resolve(
    LocalState local,
    RemoteState remote,
    List<Operation> pendingOperations,
  );
}
