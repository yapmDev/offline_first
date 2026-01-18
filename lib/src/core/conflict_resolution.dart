/// Represents the local state during conflict resolution
class LocalState {
  final Map<String, dynamic> data;
  final int timestamp;

  const LocalState({
    required this.data,
    required this.timestamp,
  });
}

/// Represents the remote state during conflict resolution
class RemoteState {
  final Map<String, dynamic> data;
  final int timestamp;

  const RemoteState({
    required this.data,
    required this.timestamp,
  });
}

/// Represents the resolution decision
enum ResolutionStrategy {
  useLocal,
  useRemote,
  merge,
  manual,
}

/// Represents the result of conflict resolution
class Resolution {
  final ResolutionStrategy strategy;
  final Map<String, dynamic>? mergedData;
  final bool requiresUserIntervention;

  const Resolution({
    required this.strategy,
    this.mergedData,
    this.requiresUserIntervention = false,
  });

  factory Resolution.useLocal() {
    return const Resolution(strategy: ResolutionStrategy.useLocal);
  }

  factory Resolution.useRemote() {
    return const Resolution(strategy: ResolutionStrategy.useRemote);
  }

  factory Resolution.merge(Map<String, dynamic> mergedData) {
    return Resolution(
      strategy: ResolutionStrategy.merge,
      mergedData: mergedData,
    );
  }

  factory Resolution.manual() {
    return const Resolution(
      strategy: ResolutionStrategy.manual,
      requiresUserIntervention: true,
    );
  }
}
