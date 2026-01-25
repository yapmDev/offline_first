import 'package:meta/meta.dart';

/// Represents the result of syncing an operation
@immutable
class SyncResult {
  /// Whether the sync was successful
  final bool success;

  /// Optional: Server-assigned ID (for create operations)
  final String? serverId;

  /// Optional: Server timestamp
  final int? serverTimestamp;

  /// Optional: Error message if failed
  final String? errorMessage;

  /// Whether this error is retryable
  final bool isRetryable;

  /// Optional: Conflict data from server
  final Map<String, dynamic>? conflictData;

  /// Optional: Updated payload from server
  ///
  /// When provided, the SyncEngine will automatically call
  /// `StorageAdapter.saveEntity()` to update the local entity with server data.
  ///
  /// **Use cases:**
  /// - Optimistic locking: Update version field after server increments it
  /// - Server-generated fields: timestamps, auto-increment IDs, computed fields
  /// - Normalized data: Update entity with server's canonical representation
  ///
  /// **Example:**
  /// ```dart
  /// if (response.statusCode == 200) {
  ///   final data = response.data;
  ///   return SyncResult.success(
  ///     resolvedPayload: {
  ///       'id': data['id'],
  ///       'name': data['name'],
  ///       'version': data['version'],  // Updated by server
  ///     },
  ///   );
  /// }
  /// ```
  final Map<String, dynamic>? resolvedPayload;

  const SyncResult({
    required this.success,
    this.serverId,
    this.serverTimestamp,
    this.errorMessage,
    this.isRetryable = true,
    this.conflictData,
    this.resolvedPayload,
  });

  /// Create a successful result
  factory SyncResult.success({
    String? serverId,
    int? serverTimestamp,
    Map<String, dynamic>? resolvedPayload,
  }) {
    return SyncResult(
      success: true,
      serverId: serverId,
      serverTimestamp: serverTimestamp,
      resolvedPayload: resolvedPayload,
    );
  }

  /// Create a failed result
  factory SyncResult.failure({
    required String errorMessage,
    bool isRetryable = true,
  }) {
    return SyncResult(
      success: false,
      errorMessage: errorMessage,
      isRetryable: isRetryable,
    );
  }

  /// Create a conflict result
  factory SyncResult.conflict({required Map<String, dynamic> conflictData}) {
    return SyncResult(
      success: false,
      conflictData: conflictData,
      isRetryable: false,
    );
  }

  @override
  String toString() {
    if (success) {
      return 'SyncResult.success(serverId: $serverId)';
    } else {
      return 'SyncResult.failure(error: $errorMessage, retryable: $isRetryable)';
    }
  }
}
