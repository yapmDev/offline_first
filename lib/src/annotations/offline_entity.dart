/// Annotation to mark a class as an offline-first entity
/// This triggers code generation for mappers, operations, and helpers
class OfflineEntity {
  /// The entity type identifier (e.g., 'product', 'user')
  final String type;

  /// The RemoteAdapter class for this entity
  final Type? adapter;

  /// The field that serves as the entity ID (defaults to 'id')
  final String idField;

  const OfflineEntity({
    required this.type,
    this.adapter,
    this.idField = 'id',
  });
}
