/// Annotation to customize field behavior in offline entities
class OfflineField {
  /// Custom name for serialization (if different from field name)
  final String? name;

  /// Whether this field should be included in updates
  final bool includeInUpdates;

  /// Default value if field is missing during deserialization
  final Object? defaultValue;

  const OfflineField({
    this.name,
    this.includeInUpdates = true,
    this.defaultValue,
  });
}
