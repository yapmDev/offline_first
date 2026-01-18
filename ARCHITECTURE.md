# Architecture Decision Records (ADR)

This document explains the key architectural decisions made in the `offline_first` package.

---

## ADR-001: Operation-Log Based Architecture

### Context
We need a way to track and synchronize changes made locally with a remote backend.

### Decision
Use an **operation-log** approach where each change is recorded as a discrete operation with a unique ID, timestamp, and payload.

### Rationale
- **Causality**: Operations have explicit ordering via timestamps
- **Auditability**: Complete history of all changes
- **Optimizability**: Operations can be reduced/squashed
- **Resilience**: Survives crashes, duplicates, and retries
- **Semantic richness**: Operations carry intent (create/update/delete)

### Alternatives Considered
- **Snapshot-based sync**: Would send entire entity state, wasteful for small changes
- **Delta-based sync**: Would track field-level diffs, more complex to implement correctly

---

## ADR-002: Local-First Architecture

### Context
Where should the source of truth reside?

### Decision
**Local storage is always the source of truth**. Changes are applied locally first, then synced to remote.

### Rationale
- **Immediate feedback**: Users see changes instantly
- **Offline capability**: App works without network
- **Conflict detection**: Local state + pending operations define truth
- **Resilience**: App survives network failures gracefully

### Trade-offs
- Requires conflict resolution mechanisms
- More complex than server-first approaches
- Eventual consistency model (not strong consistency)

---

## ADR-003: Abstract Storage and Transport

### Context
Different projects use different storage (Hive, SQLite, IndexedDB) and transports (REST, GraphQL, gRPC).

### Decision
Define **abstract interfaces** for both storage (`StorageAdapter`) and transport (`RemoteAdapter`).

### Rationale
- **Reusability**: Package works with any storage or transport
- **Testability**: Easy to mock with in-memory implementations
- **No vendor lock-in**: Users choose their own tech stack
- **Minimal dependencies**: Core package doesn't depend on HTTP or storage libraries

### Implementation
```dart
abstract class StorageAdapter {
  Future<void> saveEntity(...);
  Future<Map?> getEntity(...);
  // ...
}

abstract class RemoteAdapter<T> {
  Future<SyncResult> create(Operation op);
  Future<SyncResult> update(Operation op);
  // ...
}
```

---

## ADR-004: Operation Squashing

### Context
Rapidly changing entities can generate many operations (e.g., typing in a text field).

### Decision
Implement an **OperationReducer** that merges consecutive operations on the same entity.

### Rationale
- **Network efficiency**: Fewer requests to backend
- **Faster sync**: Less operations to process
- **Bandwidth savings**: Critical for mobile/constrained networks

### Rules
- `CREATE` + `UPDATE` → `CREATE` (with merged payload)
- `CREATE` + `DELETE` → cancelled (entity never existed remotely)
- `UPDATE` + `UPDATE` → `UPDATE` (merged)
- `UPDATE` + `DELETE` → `DELETE`

### Trade-offs
- Slightly more complex sync logic
- Must ensure squashing preserves semantics
- Not all operation types can be squashed (custom operations may not be reducible)

---

## ADR-005: Idempotency via Operation IDs

### Context
Network failures, retries, and duplicates are inevitable in distributed systems.

### Decision
Every operation has a unique UUID (`operationId`) that backends use for deduplication.

### Rationale
- **Safe retries**: Can retry operations without side effects
- **Duplicate detection**: Backend can detect and ignore duplicate requests
- **Crash recovery**: Can resume sync after failures

### Implementation
Remote adapters include `operationId` in requests (e.g., `X-Operation-Id` header). Backend checks if operation was already processed:

```javascript
if (await db.hasProcessedOperation(operationId)) {
  return { status: 'already_processed' };
}
```

---

## ADR-006: Pluggable Conflict Resolution

### Context
Conflicts are inevitable when local and remote state diverge.

### Decision
Define a `ConflictResolver` interface with pluggable strategies.

### Rationale
- **Domain-specific**: Different domains need different strategies
- **Flexibility**: Users can implement custom resolvers
- **Sensible defaults**: Provide LastWriteWins and FieldLevelMerge out of the box

### Strategies
1. **Last Write Wins** (default): Compare timestamps
2. **Field-Level Merge**: Merge non-conflicting fields
3. **Manual**: Require user intervention
4. **Custom**: Users implement their own logic

---

## ADR-007: Code Generation for Boilerplate

### Context
Users would need to write repetitive `toMap`/`fromMap` methods for every entity.

### Decision
Use **Dart annotations** + **build_runner** to generate serialization code.

### Rationale
- **Developer experience**: Less boilerplate, fewer bugs
- **Consistency**: Generated code follows patterns correctly
- **Maintainability**: Changes to generation logic apply everywhere

### Example
```dart
@OfflineEntity(type: 'product')
class Product {
  final String id;
  final String name;
}

// Generates:
// - toMap() method
// - fromMap() factory
// - entityType getter
// - entityId getter
```

---

## ADR-008: Sync Engine Responsibilities

### Context
What should orchestrate the sync process?

### Decision
Create a dedicated `SyncEngine` that:
1. Fetches pending operations
2. Reduces/squashes them
3. Syncs in order via remote adapters
4. Handles retries, failures, and conflicts
5. Emits status events

### Rationale
- **Separation of concerns**: Store is simple API, engine handles complexity
- **Testability**: Can test sync logic in isolation
- **Observability**: Status stream for UI feedback

---

## ADR-009: No Built-in Network Detection

### Context
Should the package detect online/offline state?

### Decision
**No**. Network detection is **pluggable** via external packages.

### Rationale
- **Platform differences**: Network detection varies by platform (mobile, web, desktop)
- **User control**: Some apps have custom connectivity logic (VPN, proxy)
- **Minimal dependencies**: Keep package lightweight
- **Flexibility**: Users can use `connectivity_plus`, custom logic, or manual triggers

### Usage
```dart
// User's responsibility
connectivity.onConnectivityChanged.listen((status) {
  if (status != ConnectivityResult.none) {
    store.sync();
  }
});
```

---

## ADR-010: Transactions for Storage Operations

### Context
Some operations need atomicity (e.g., squashing multiple operations).

### Decision
Provide a `executeTransaction` method in `StorageAdapter`.

### Rationale
- **Atomicity**: All-or-nothing semantics
- **Data integrity**: Prevents partial state
- **Flexibility**: Optional, not all storage backends support transactions

### Implementation
```dart
abstract class StorageAdapter {
  Future<bool> executeTransaction(
    Future<void> Function(StorageAdapter) operations
  );
}
```

---

## ADR-011: Status Streams for Observability

### Context
UIs need to show sync progress and status.

### Decision
`SyncEngine` exposes a `Stream<SyncStatusEvent>` with status, progress, and errors.

### Rationale
- **Reactive**: UIs can listen and update automatically
- **Informative**: Users see what's happening
- **Debugging**: Developers can log sync events

### Events
```dart
SyncStatusEvent(
  status: SyncStatus.syncing,
  totalOperations: 10,
  completedOperations: 3,
  errorMessage: null,
)
```

---

## ADR-012: Test-Friendly Design

### Context
The package must be thoroughly testable.

### Decision
- Provide `InMemoryStorageAdapter` for testing
- All core components are pure Dart (no Flutter dependencies in core)
- Dependencies are injected (DI-friendly)
- Abstractions enable mocking

### Benefits
- **Fast tests**: No I/O with in-memory storage
- **Isolated tests**: Mock adapters and resolvers
- **CI-friendly**: No platform-specific dependencies

---

## Future Considerations

### Potential Future ADRs

1. **Batch Sync Optimization**: Send multiple operations in one request
2. **Automatic Retry with Exponential Backoff**: Smarter retry logic
3. **Operation Expiration/TTL**: Remove very old operations
4. **Encryption Support**: Encrypt storage and operations
5. **Multi-Device Sync**: Handle operations from multiple devices
6. **Real-time Sync**: WebSocket-based live sync
7. **Schema Migrations**: Handle entity schema changes

---

## Conclusion

These architectural decisions prioritize:
- **Reusability** (generic, not domain-specific)
- **Flexibility** (pluggable adapters and strategies)
- **Resilience** (handles failures gracefully)
- **Simplicity** (clean API, hidden complexity)
- **Testability** (easy to test all components)

The result is a production-ready offline-first package suitable for real-world applications.
