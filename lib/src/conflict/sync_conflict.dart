import '../core/operation.dart';

/// How to settle a conflict — see `OfflineStore.resolveConflict`.
enum ConflictChoice {
  /// Re-send the local write, rebased onto the server's current version.
  ///
  /// Rebasing is the point: re-sending unchanged would fail the same version
  /// check and conflict again.
  keepLocal,

  /// Drop the local write and adopt the server's state locally.
  keepRemote,

  /// Drop the local write without touching local state.
  ///
  /// For when the decision moves elsewhere — escalated to someone else,
  /// recorded as a ticket — and the queue should stop carrying it.
  discard,
}

/// A local write the server refused because it was made on top of stale data.
///
/// Everything needed to present the choice is here, so a conflict raised while
/// syncing in the background can be settled later, after a restart, without
/// re-fetching (which would show a third state rather than the one the write
/// actually lost against).
class SyncConflict {
  const SyncConflict(this.operation);

  /// The operation that was refused, parked in
  /// [OperationStatus.conflicted].
  final Operation operation;

  String get operationId => operation.operationId;

  String get entityType => operation.entityType;

  String get entityId => operation.entityId;

  /// What this device tried to write.
  Map<String, dynamic> get localPayload => operation.payload;

  /// The server's state of the entity at the moment it refused the write.
  ///
  /// Null when the backend refused without returning its state and
  /// `fetchRemoteState` could not supply it either — the conflict is then
  /// only resolvable as keep-local or discard, since there is nothing to
  /// compare against or adopt.
  Map<String, dynamic>? get serverState => operation.conflictData;

  /// Version to rebase onto when keeping the local write.
  int? get serverVersion => operation.conflictServerVersion;

  /// Version this device believed it was editing.
  int? get baseVersion => operation.baseVersion;

  @override
  String toString() =>
      'SyncConflict(${operation.entityType}/${operation.entityId}, '
      'base: ${operation.baseVersion}, server: $serverVersion)';
}
