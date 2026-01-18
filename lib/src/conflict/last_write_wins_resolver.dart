import '../core/operation.dart';
import '../core/conflict_resolution.dart';
import 'conflict_resolver.dart';

/// Last Write Wins conflict resolution strategy
/// Compares timestamps and chooses the most recent version
class LastWriteWinsResolver extends ConflictResolver {
  @override
  Future<Resolution> resolve(
    LocalState local,
    RemoteState remote,
    List<Operation> pendingOperations,
  ) async {
    // Compare timestamps
    if (local.timestamp > remote.timestamp) {
      // Local is newer, keep local changes
      return Resolution.useLocal();
    } else if (remote.timestamp > local.timestamp) {
      // Remote is newer, use remote version
      return Resolution.useRemote();
    } else {
      // Same timestamp (rare), prefer local
      return Resolution.useLocal();
    }
  }
}
