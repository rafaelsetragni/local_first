part of '../../local_first.dart';

/// Utility helpers for conflict resolution.
sealed class ConflictUtil {
  /// Default LWW conflict resolver.
  ///
  /// Priority:
  /// 1. `serverSequence` (higher wins; if only one has sequence, it wins).
  /// 2. `syncCreatedAt` (more recent wins).
  /// 3. Fallback: keep local.
  static LocalFirstEvent<U> lastWriteWins<U extends Object>(
    LocalFirstEvent<U> local,
    LocalFirstEvent<U> remote,
  ) {
    final localSeq = local.serverSequence;
    final remoteSeq = remote.serverSequence;

    if (localSeq != null || remoteSeq != null) {
      if (localSeq == null) return remote;
      if (remoteSeq == null) return local;
      if (remoteSeq != localSeq) {
        return remoteSeq > localSeq ? remote : local;
      }
    }

    if (local.syncCreatedAt.isAfter(remote.syncCreatedAt)) {
      return local;
    }
    // Tie -> prefer remote
    return remote;
  }
}
