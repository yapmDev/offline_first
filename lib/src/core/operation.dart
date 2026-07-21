import 'package:meta/meta.dart';

/// Represents the type of operation to be performed
enum OperationType {
  create,
  update,
  delete,
  custom,
}

/// Represents the current status of an operation
enum OperationStatus {
  pending,
  syncing,
  synced,

  /// Failed for a retryable reason (network, 5xx) after exhausting
  /// [SyncConfig.maxRetries]. Still eligible for a new attempt on the next
  /// sync — the condition that caused it is expected to clear on its own.
  failed,

  /// Failed for a reason retrying cannot fix (4xx, validation, business
  /// rule). Never attempted again automatically: it needs the user to edit,
  /// discard or otherwise act on it.
  failedPermanent,

  /// The server refused the write because it was made on top of a version
  /// that has since moved on. Parked with the server's state attached until
  /// someone decides what to keep — see `OfflineStore.resolveConflict`.
  conflicted,
}

/// Represents a domain operation to be synced
@immutable
class Operation {
  /// Unique identifier for this operation
  final String operationId;

  /// Type of entity this operation affects (e.g., 'product', 'user')
  final String entityType;

  /// Specific entity instance ID
  final String entityId;

  /// Type of operation
  final OperationType operationType;

  /// Operation payload (entity data or partial updates)
  final Map<String, dynamic> payload;

  /// Logical timestamp for ordering operations
  final int timestamp;

  /// Current status of the operation
  final OperationStatus status;

  /// Device/client identifier
  final String deviceId;

  /// Optional: Number of retry attempts
  final int retryCount;

  /// Optional: Last error message if failed
  final String? errorMessage;

  /// Optional: Custom operation name for OperationType.custom
  final String? customOperationName;

  /// Version of the entity this write was made on top of.
  ///
  /// Sent to the backend so it can refuse the write if the entity has moved
  /// on since — that refusal is what turns a silent overwrite into a
  /// conflict. Null means the caller does not version this entity, which
  /// leaves the backend's previous last-write-wins behaviour untouched.
  final int? baseVersion;

  /// Server state captured when this operation was refused as conflicting.
  ///
  /// Kept on the operation so the conflict survives a restart: whoever
  /// resolves it may do so hours later, and re-fetching would show a third
  /// state rather than the one the write actually lost against.
  final Map<String, dynamic>? conflictData;

  /// Entity version the server reported when refusing this operation.
  final int? conflictServerVersion;

  const Operation({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.payload,
    required this.timestamp,
    required this.status,
    required this.deviceId,
    this.retryCount = 0,
    this.errorMessage,
    this.customOperationName,
    this.baseVersion,
    this.conflictData,
    this.conflictServerVersion,
  });

  /// Whether this operation is parked waiting on a conflict decision.
  bool get isConflicted => status == OperationStatus.conflicted;

  /// Re-queue this operation on top of [baseVersion], dropping the conflict.
  ///
  /// Rebasing is what makes "keep mine" terminal instead of circular: re-sending
  /// the operation unchanged would hit the very same version check and conflict
  /// again, forever.
  Operation rebased({
    required int? baseVersion,
    Map<String, dynamic>? payload,
  }) {
    return Operation(
      operationId: operationId,
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      payload: payload ?? this.payload,
      timestamp: timestamp,
      status: OperationStatus.pending,
      deviceId: deviceId,
      retryCount: 0,
      customOperationName: customOperationName,
      baseVersion: baseVersion,
    );
  }

  /// Create a copy with modified fields
  Operation copyWith({
    String? operationId,
    String? entityType,
    String? entityId,
    OperationType? operationType,
    Map<String, dynamic>? payload,
    int? timestamp,
    OperationStatus? status,
    String? deviceId,
    int? retryCount,
    String? errorMessage,
    String? customOperationName,
    int? baseVersion,
    Map<String, dynamic>? conflictData,
    int? conflictServerVersion,
  }) {
    return Operation(
      operationId: operationId ?? this.operationId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      deviceId: deviceId ?? this.deviceId,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
      customOperationName: customOperationName ?? this.customOperationName,
      baseVersion: baseVersion ?? this.baseVersion,
      conflictData: conflictData ?? this.conflictData,
      conflictServerVersion: conflictServerVersion ?? this.conflictServerVersion,
    );
  }

  /// Convert to Map for storage
  Map<String, dynamic> toMap() {
    return {
      'operationId': operationId,
      'entityType': entityType,
      'entityId': entityId,
      'operationType': operationType.name,
      'payload': payload,
      'timestamp': timestamp,
      'status': status.name,
      'deviceId': deviceId,
      'retryCount': retryCount,
      'errorMessage': errorMessage,
      'customOperationName': customOperationName,
      'baseVersion': baseVersion,
      'conflictData': conflictData,
      'conflictServerVersion': conflictServerVersion,
    };
  }

  /// Create from Map (from storage)
  factory Operation.fromMap(Map<String, dynamic> map) {
    return Operation(
      operationId: map['operationId'] as String,
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      operationType: OperationType.values.firstWhere(
        (e) => e.name == map['operationType'],
      ),
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      timestamp: map['timestamp'] as int,
      status: OperationStatus.values.firstWhere(
        (e) => e.name == map['status'],
      ),
      deviceId: map['deviceId'] as String,
      retryCount: map['retryCount'] as int? ?? 0,
      errorMessage: map['errorMessage'] as String?,
      customOperationName: map['customOperationName'] as String?,
      baseVersion: map['baseVersion'] as int?,
      conflictData: map['conflictData'] == null
          ? null
          : Map<String, dynamic>.from(map['conflictData'] as Map),
      conflictServerVersion: map['conflictServerVersion'] as int?,
    );
  }

  @override
  String toString() {
    return 'Operation(id: $operationId, type: $operationType, '
        'entity: $entityType/$entityId, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Operation && other.operationId == operationId;
  }

  @override
  int get hashCode => operationId.hashCode;
}
