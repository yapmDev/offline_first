# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — conflict detection and resolution

- **`Operation.baseVersion`**: the entity version a write was made on top of,
  sent to the backend so it can refuse writes built on stale data. Omitting it
  keeps the backend's previous last-write-wins behaviour, so adopting this is
  incremental. `logUpdate`/`logDelete`/`logCustom` take it as a named argument.
- **`OperationStatus.conflicted`**: a refused write is now *parked* with the
  server's state attached rather than failed. It is excluded from the sync
  queue, survives restarts, and is settled by a decision — not by retrying.
- **`SyncConflict` + `OfflineStore.conflictStream` / `getConflicts()` /
  `getConflictCount()`**: everything needed to present the choice, including
  the server state captured at the moment of refusal. Re-fetching later would
  show a third state rather than the one the write actually lost against.
- **`OfflineStore.resolveConflict(id, choice, {payload})`** with
  `ConflictChoice.keepLocal` / `keepRemote` / `discard`. `keepLocal` **rebases**
  the operation onto the server's version, optionally replacing the payload —
  which is how a merge is applied, since only the caller knows the shape its
  backend expects.
- **`OfflineStore.getFailedOperations()` / `retryOperation` /
  `discardOperation`**: permanently failed operations were unreachable, so a
  write that could never be sent had no way out of the queue.
- **`SyncResult.conflict` now carries `serverVersion` and `serverTimestamp`**.
  Both matter: without the version a resolved conflict retries onto the same
  stale base and conflicts again, and without the timestamp `LastWriteWinsResolver`
  falls back to the local clock and compares a value against itself.

### Changed — conflict detection and resolution

- **A conflict no longer needs a `ConflictResolver`**. Previously, no resolver
  meant the operation was marked failed with "no resolver configured" — the
  common case produced a dead end. A resolver now gets first say if configured,
  and anything it declines is parked for a person.
- **A stalled entity holds back its own later writes for the rest of the pass**,
  while other entities keep syncing. Writes queued after a refused one were
  built on the same assumption it just disproved.
- **A missing `RemoteAdapter` is now `failedPermanent`** rather than `failed`.
  Retrying never registers an adapter, so it re-sent forever.
- **`fetchRemoteState` is finally used**: it fills in the server state when the
  backend refuses without returning one. It had been declared, implemented by
  adapters, and never called.

### Fixed — conflict detection and resolution

- **Resolving "keep mine" no longer loops forever.** It re-queued the operation
  unchanged, so it hit the same version check and conflicted again on every
  sync. It now rebases onto the server's version.
- **A conflict on an entity deleted locally no longer discards the write
  silently.** It removed the operation and reported success.
- **A conflict resolver that throws no longer loses the write.** It was marked
  failed; it is now parked for a person to settle.

### Migration

`StorageAdapter` implementations must add `getOperationsByStatus` and exclude
`conflicted` from `getPendingOperations`.

### Fixed

- **Non-retryable failures no longer retry forever**: `_handleFailure` collapsed
  "the network was down" and "the server rejected this" into a single `failed`
  status. Any storage adapter that made `failed` operations eligible for sync
  (the documented behaviour, so a network failure eventually recovers) therefore
  re-sent 4xx-rejected operations on every single sync, forever, and kept the
  pending count permanently above zero.
- **Orphaned operations are recovered**: an operation left in `syncing` by a
  process that died mid-flight was excluded from `getPendingOperations()`, so it
  was never retried *and* never counted as pending — an invisible lost write.

### Added

- **`OperationStatus.failedPermanent`**: terminal status for failures retrying
  cannot fix. Excluded from the sync queue; needs the user to act on it.
- **`StorageAdapter.getOperationsForType(entityType)`** and
  **`OfflineStore.unsyncedEntityIds(entityType)`**: the set of entity ids that
  still carry a local write the server has not acknowledged. A local-first
  refresh must skip these — overwriting one drops the local edit, and pruning an
  id the server has never seen deletes the record outright.

### Changed

- **`StorageAdapter.getPendingOperations()` contract is now documented**:
  eligible means `pending`, `syncing` (orphan recovery) and `failed`, never
  `synced` or `failedPermanent`. `InMemoryStorageAdapter` returned only
  `pending`, which silently diverged from what real adapters were doing.

### Migration

Storage adapter implementations must add `getOperationsForType` and align
`getPendingOperations`/`getPendingOperationsCount` with the contract above.
Persisted operations are unaffected: `failedPermanent` only appears on new
failures.

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
