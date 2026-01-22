part of '../../local_first.dart';

/// Helpers to resolve conflicts between local and remote events.
sealed class ConflictUtil {
  /// Picks the event considered newest by the provided selector, preserving
  /// sync metadata from the chosen event.
  static LocalFirstEvent<T> lastWriteWins<T>(
    LocalFirstEvent<T> local,
    LocalFirstEvent<T> remote,
  ) {
    final localUpdated = local.syncCreatedAt;
    final remoteUpdated = remote.syncCreatedAt;

    if (localUpdated.isAfter(remoteUpdated)) {
      return local;
    }
    return remote;
  }
}
