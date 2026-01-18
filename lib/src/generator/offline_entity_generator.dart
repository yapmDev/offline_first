import 'dart:async';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import '../annotations/offline_entity.dart';

/// Generator for @OfflineEntity annotated classes
class OfflineEntityGenerator extends GeneratorForAnnotation<OfflineEntity> {
  @override
  FutureOr<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@OfflineEntity can only be applied to classes',
        element: element,
      );
    }

    final classElement = element;
    final className = classElement.name;
    final entityType = annotation.read('type').stringValue;
    final idField = annotation.read('idField').stringValue;

    final buffer = StringBuffer();

    // Generate extension with helper methods
    buffer.writeln('extension ${className}OfflineExtension on $className {');
    buffer.writeln('  /// Convert to Map for storage');
    buffer.writeln('  Map<String, dynamic> toMap() {');
    buffer.writeln('    return {');

    // Generate toMap fields
    for (final field in classElement.fields) {
      if (_shouldIgnoreField(field)) continue;

      final fieldName = field.name;
      final customName = _getCustomFieldName(field) ?? fieldName;

      buffer.writeln("      '$customName': $fieldName,");
    }

    buffer.writeln('    };');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate fromMap factory
    buffer.writeln('  /// Create from Map (from storage)');
    buffer.writeln('  static $className fromMap(Map<String, dynamic> map) {');
    buffer.writeln('    return $className(');

    for (final field in classElement.fields) {
      if (_shouldIgnoreField(field)) continue;

      final fieldName = field.name;
      final customName = _getCustomFieldName(field) ?? fieldName;
      final defaultValue = _getDefaultValue(field);

      final fieldType = field.type.toString();
      final isNullable = field.type.nullabilitySuffix.toString() == 'NullabilitySuffix.question';

      if (isNullable) {
        buffer.writeln("      $fieldName: map['$customName'] as $fieldType,");
      } else if (defaultValue != null) {
        buffer.writeln(
            "      $fieldName: map['$customName'] as $fieldType? ?? $defaultValue,");
      } else {
        buffer.writeln("      $fieldName: map['$customName'] as $fieldType,");
      }
    }

    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate entity type getter
    buffer.writeln('  /// Get the entity type');
    buffer.writeln("  String get entityType => '$entityType';");
    buffer.writeln();

    // Generate entity ID getter
    buffer.writeln('  /// Get the entity ID');
    buffer.writeln('  String get entityId => $idField;');
    buffer.writeln('}');
    buffer.writeln();

    // Generate helper class for operations
    buffer.writeln('/// Helper class for $className operations');
    buffer.writeln('class ${className}Operations {');
    buffer.writeln("  static const String entityType = '$entityType';");
    buffer.writeln("  static const String idField = '$idField';");
    buffer.writeln('}');

    return buffer.toString();
  }

  bool _shouldIgnoreField(FieldElement field) {
    // Check for @OfflineIgnore annotation
    final hasIgnore = field.metadata.any((meta) {
      final element = meta.element;
      if (element is! ConstructorElement) return false;
      return element.returnType.element.name == 'OfflineIgnore';
    });

    // Also ignore static and const fields
    return hasIgnore || field.isStatic || field.isConst;
  }

  String? _getCustomFieldName(FieldElement field) {
    for (final meta in field.metadata) {
      final element = meta.element;
      if (element is! ConstructorElement) continue;
      if (element.returnType.element.name != 'OfflineField') continue;

      final annotation = meta.computeConstantValue();
      final nameField = annotation?.getField('name');
      if (nameField != null && !nameField.isNull) {
        return nameField.toStringValue();
      }
    }
    return null;
  }

  String? _getDefaultValue(FieldElement field) {
    for (final meta in field.metadata) {
      final element = meta.element;
      if (element is! ConstructorElement) continue;
      if (element.returnType.element.name != 'OfflineField') continue;

      final annotation = meta.computeConstantValue();
      final defaultValueField = annotation?.getField('defaultValue');
      if (defaultValueField != null && !defaultValueField.isNull) {
        final type = defaultValueField.type.toString();
        if (type == 'String') {
          return "'${defaultValueField.toStringValue()}'";
        } else if (type == 'int' || type == 'double' || type == 'bool') {
          return defaultValueField.toString();
        }
      }
    }
    return null;
  }
}
