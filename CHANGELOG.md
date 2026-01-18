# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
