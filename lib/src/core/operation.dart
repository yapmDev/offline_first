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
  failed,
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
  });

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
