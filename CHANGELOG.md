# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-01-25

### Documentation

- **Enhanced `resolvedPayload` documentation**: Added comprehensive documentation for the `resolvedPayload` feature in `SyncResult`
- **Updated USAGE_MODES.md**: Renamed "Operation Logging Mode" to "Hybrid Mode" to better reflect actual usage with server data sync
- **Added RESOLVED_PAYLOAD.md**: New dedicated guide explaining `resolvedPayload` with examples, flow diagrams, and troubleshooting
- **Updated ADVANCED_USAGE.md**: Added complete "Optimistic Locking with Version Fields" section with backend and frontend examples
- **Updated README.md**: Added mention of `resolvedPayload` in Remote Adapter section
- **Improved code documentation**: Added detailed comments to `SyncResult.resolvedPayload` field explaining use cases and examples
- **Fixed misleading examples**: Updated HTTP adapter examples to show correct usage of `resolvedPayload`

### Changed

- **StorageAdapter usage pattern**: Clarified that `saveEntity()` should be implemented (not throw `UnsupportedError`) when using Hybrid Mode with server-managed fields
- **Hybrid Mode architecture**: Better explained the separation of concerns where app manages primary storage but allows SyncEngine to update entities with server data

### Why These Changes

The previous documentation suggested that apps using their own storage (Mode 1) should throw `UnsupportedError` for entity methods in `StorageAdapter`. However, this breaks the `resolvedPayload` flow, which is essential for syncing server-managed fields like version numbers for optimistic locking. The updated documentation now clearly explains:

1. How `resolvedPayload` works and when to use it
2. That `StorageAdapter.saveEntity()` must be implemented for server data sync
3. Complete examples of optimistic locking implementation
4. Troubleshooting guide for common issues

## [0.1.0] - 2026-01-17

### Added
- Initial release of offline_first package
- Operation-log based architecture
- Incremental sync with remote backends
- Operation squashing/reduction
- Pluggable remote adapters (transport agnostic)
- Pluggable storage adapters
- Conflict resolution strategies (LastWriteWins, FieldLevelMerge)
- Code generation with annotations (@OfflineEntity, @OfflineField, @OfflineIgnore)
- InMemoryStorageAdapter for testing
- Comprehensive test suite
- Flutter Web example application
- Full documentation and architectural diagrams

### Features
- ✅ Operation-based sync (no snapshots)
- ✅ Local-first architecture
- ✅ Automatic operation optimization
- ✅ Idempotent operations
- ✅ Retry logic with configurable max attempts
- ✅ Real-time sync status streams
- ✅ Transaction support for storage operations

### Documentation
- Complete README with architecture diagrams
- Usage examples and best practices
- Production considerations guide
- API documentation
