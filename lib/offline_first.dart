/// A generic, reusable offline-first architecture package based on operation-log
/// with incremental sync, operation squashing, and pluggable remote adapters.
library offline_first;

// Core
export 'src/core/operation.dart';
export 'src/core/operation_log.dart';
export 'src/core/remote_adapter.dart';
export 'src/core/sync_result.dart';
export 'src/core/offline_store.dart';
export 'src/core/conflict_resolution.dart';

// Storage
export 'src/storage/storage_adapter.dart';
export 'src/storage/in_memory_storage_adapter.dart';

// Sync
export 'src/sync/sync_engine.dart';
export 'src/sync/operation_reducer.dart';

// Conflict Resolution
export 'src/conflict/conflict_resolver.dart';
export 'src/conflict/last_write_wins_resolver.dart';
export 'src/conflict/field_level_merge_resolver.dart';

// Annotations
export 'src/annotations/offline_entity.dart';
export 'src/annotations/offline_field.dart';
export 'src/annotations/offline_ignore.dart';
export 'src/annotations/conflict_policy.dart';
