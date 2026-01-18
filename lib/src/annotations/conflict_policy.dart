/// Conflict resolution strategy for an entity or field
enum ConflictStrategy {
  lastWriteWins,
  firstWriteWins,
  manual,
}

/// Annotation to specify conflict resolution policy
class ConflictPolicy {
  final ConflictStrategy strategy;

  const ConflictPolicy(this.strategy);
}
