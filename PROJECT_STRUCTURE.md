# Project Structure

This document provides an overview of the `offline_first` package structure.

## Directory Layout

```
offline_first/
├── lib/                              # Main package source
│   ├── src/                          # Internal implementation
│   │   ├── core/                     # Core domain logic
│   │   │   ├── operation.dart        # Operation model
│   │   │   ├── operation_log.dart    # Operation log manager
│   │   │   ├── remote_adapter.dart   # Abstract remote adapter
│   │   │   ├── sync_result.dart      # Sync result model
│   │   │   ├── offline_store.dart    # Main API (OfflineStore)
│   │   │   └── conflict_resolution.dart # Conflict resolution models
│   │   │
│   │   ├── storage/                  # Storage abstractions
│   │   │   ├── storage_adapter.dart         # Abstract storage interface
│   │   │   └── in_memory_storage_adapter.dart # In-memory implementation
│   │   │
│   │   ├── sync/                     # Sync logic
│   │   │   ├── sync_engine.dart      # Sync orchestration
│   │   │   └── operation_reducer.dart # Operation squashing
│   │   │
│   │   ├── conflict/                 # Conflict resolution
│   │   │   ├── conflict_resolver.dart        # Abstract resolver
│   │   │   ├── last_write_wins_resolver.dart # LWW strategy
│   │   │   └── field_level_merge_resolver.dart # Field merge strategy
│   │   │
│   │   ├── annotations/              # Code generation annotations
│   │   │   ├── offline_entity.dart   # @OfflineEntity annotation
│   │   │   ├── offline_field.dart    # @OfflineField annotation
│   │   │   ├── offline_ignore.dart   # @OfflineIgnore annotation
│   │   │   └── conflict_policy.dart  # @ConflictPolicy annotation
│   │   │
│   │   └── generator/                # Code generators
│   │       └── offline_entity_generator.dart # Entity code generator
│   │
│   ├── offline_first.dart            # Public API exports
│   └── generator.dart                # Builder exports
│
├── example/                          # Example applications
│   └── flutter_web_app/              # Flutter Web demo
│       ├── lib/
│       │   ├── models/
│       │   │   ├── product.dart              # Example entity
│       │   │   └── product.offline.g.dart    # Generated code
│       │   ├── adapters/
│       │   │   └── product_remote_adapter.dart # Example adapter
│       │   ├── backend/
│       │   │   └── mock_backend.dart         # Mock server
│       │   └── main.dart             # Main app
│       ├── web/
│       │   ├── index.html
│       │   └── manifest.json
│       ├── pubspec.yaml
│       └── README.md
│
├── test/                             # Unit tests
│   ├── operation_test.dart           # Operation model tests
│   ├── operation_reducer_test.dart   # Squashing logic tests
│   ├── storage_adapter_test.dart     # Storage tests
│   ├── conflict_resolver_test.dart   # Conflict resolution tests
│   └── offline_store_test.dart       # Integration tests
│
├── pubspec.yaml                      # Package dependencies
├── build.yaml                        # Build configuration
├── analysis_options.yaml             # Linter configuration
├── .gitignore                        # Git ignore rules
├── LICENSE                           # MIT License
├── CHANGELOG.md                      # Version history
├── README.md                         # Main documentation
├── ARCHITECTURE.md                   # Architecture decisions
├── ADVANCED_USAGE.md                 # Advanced examples
└── PROJECT_STRUCTURE.md              # This file
```

---

## Key Components

### Core (`lib/src/core/`)

The heart of the package, containing the main domain models and logic:

- **Operation**: Immutable representation of a change
- **OperationLog**: Manages the append-only operation log
- **RemoteAdapter**: Abstract interface for backend communication
- **OfflineStore**: Main API that users interact with
- **SyncResult**: Result of syncing an operation

### Storage (`lib/src/storage/`)

Storage abstraction layer:

- **StorageAdapter**: Abstract interface for storage operations
- **InMemoryStorageAdapter**: Reference implementation for testing

Users can implement custom adapters for:
- Hive
- SQLite (sqflite)
- IndexedDB (for web)
- Shared Preferences
- Or any other storage backend

### Sync (`lib/src/sync/`)

Synchronization logic:

- **SyncEngine**: Orchestrates the sync process
- **OperationReducer**: Optimizes operation queues (squashing)

### Conflict Resolution (`lib/src/conflict/`)

Pluggable conflict resolution:

- **ConflictResolver**: Abstract base class
- **LastWriteWinsResolver**: Default timestamp-based strategy
- **FieldLevelMergeResolver**: Field-level merge strategy

### Annotations (`lib/src/annotations/`)

Annotations for code generation:

- **@OfflineEntity**: Marks a class as an offline entity
- **@OfflineField**: Customizes field serialization
- **@OfflineIgnore**: Excludes fields from serialization
- **@ConflictPolicy**: Specifies conflict resolution strategy

### Generator (`lib/src/generator/`)

Code generation implementation:

- **OfflineEntityGenerator**: Generates serialization code using build_runner

---

## Public API Surface

Users primarily interact with these exports from `lib/offline_first.dart`:

### Core Classes
- `OfflineStore` - Main API
- `Operation` - Operation model
- `OperationType` - Enum of operation types
- `OperationStatus` - Enum of operation statuses
- `SyncResult` - Result of sync operations
- `SyncStatus` - Current sync status
- `SyncConfig` - Sync configuration

### Storage
- `StorageAdapter` - Abstract storage interface
- `InMemoryStorageAdapter` - In-memory implementation

### Sync
- `SyncEngine` - Sync orchestrator
- `OperationReducer` - Squashing interface
- `DefaultOperationReducer` - Default squashing implementation

### Conflict Resolution
- `ConflictResolver` - Abstract resolver
- `LastWriteWinsResolver` - LWW implementation
- `FieldLevelMergeResolver` - Field merge implementation
- `Resolution` - Resolution result
- `ResolutionStrategy` - Resolution strategy enum

### Annotations
- `@OfflineEntity()` - Entity annotation
- `@OfflineField()` - Field annotation
- `@OfflineIgnore()` - Ignore annotation
- `@ConflictPolicy()` - Conflict policy annotation

---

## Data Flow

```
User Action (UI)
    ↓
OfflineStore.save() / delete()
    ↓
Storage: Apply change locally (SOURCE OF TRUTH)
    ↓
OperationLog: Append operation
    ↓
[When sync triggered]
    ↓
SyncEngine.sync()
    ↓
OperationReducer: Squash operations (optional)
    ↓
RemoteAdapter: Translate to backend calls
    ↓
Backend: Process with idempotency check
    ↓
[On success] OperationLog: Remove operation
[On conflict] ConflictResolver: Resolve and retry
[On failure] OperationLog: Mark for retry
```

---

## Extension Points

The package is designed to be extended at these points:

1. **StorageAdapter** - Implement for your storage backend
2. **RemoteAdapter** - Implement for your transport layer
3. **ConflictResolver** - Implement custom conflict resolution
4. **OperationReducer** - Implement custom squashing rules

---

## Dependencies

### Production Dependencies
- `uuid` - For generating unique operation IDs
- `meta` - For annotations

### Development Dependencies
- `build_runner` - For code generation
- `source_gen` - For code generation
- `analyzer` - For code generation
- `test` - For unit testing
- `lints` - For code quality

### No Platform Dependencies
The core package has **no Flutter or platform-specific dependencies**, making it:
- Testable with pure Dart tests
- Usable in non-Flutter Dart projects
- Easy to CI/CD

---

## Testing Strategy

### Unit Tests (`test/`)
- Test individual components in isolation
- Use `InMemoryStorageAdapter` for fast tests
- Mock remote adapters for sync tests

### Integration Tests (Example App)
- Test real-world scenarios
- Demonstrate usage patterns
- Validate end-to-end flows

### Test Coverage
All core components have comprehensive test coverage:
- ✅ Operation serialization
- ✅ Storage operations
- ✅ Operation squashing
- ✅ Conflict resolution
- ✅ Sync engine behavior

---

## Build Process

### For Package Development
```bash
# Get dependencies
dart pub get

# Run tests
dart test

# Analyze code
dart analyze
```

### For Code Generation (in consuming projects)
```bash
# Generate code
dart run build_runner build

# Watch for changes
dart run build_runner watch
```

### For Example App
```bash
cd example/flutter_web_app
flutter pub get
flutter run -d chrome
```

---

## Documentation Files

- **README.md** - Quick start and overview
- **ARCHITECTURE.md** - Architectural decisions and rationale
- **ADVANCED_USAGE.md** - Advanced patterns and examples
- **PROJECT_STRUCTURE.md** - This file
- **CHANGELOG.md** - Version history
- **example/flutter_web_app/README.md** - Example app guide

---

## Publishing Checklist

Before publishing to pub.dev:

- [ ] All tests pass (`dart test`)
- [ ] No analyzer warnings (`dart analyze`)
- [ ] Version bumped in `pubspec.yaml`
- [ ] CHANGELOG.md updated
- [ ] README.md is clear and complete
- [ ] Example app works
- [ ] License file present (MIT)
- [ ] Code is well documented
- [ ] API is stable

---

## Contributing

When contributing:

1. Follow the existing code style
2. Add tests for new features
3. Update documentation
4. Run `dart analyze` and fix warnings
5. Run `dart test` and ensure all pass

---

## Version Strategy

This package follows [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes to public API
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, backward compatible

Current version: **0.1.0** (initial release)

---

## Future Structure Additions

Planned additions to the project structure:

- `lib/src/storage/hive_storage_adapter.dart` - Hive implementation
- `lib/src/storage/sqlite_storage_adapter.dart` - SQLite implementation
- `lib/src/adapters/http_adapter.dart` - Generic HTTP adapter
- `lib/src/encryption/` - Encryption support
- `lib/src/migration/` - Schema migration tools

---

This structure balances:
- **Simplicity** (easy to understand)
- **Extensibility** (easy to customize)
- **Testability** (easy to test)
- **Maintainability** (easy to maintain)
