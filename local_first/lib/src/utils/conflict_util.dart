part of '../../local_first.dart';

/// Helpers to resolve conflicts between local and remote events.
class ConflictUtil {
  /// Picks the event whose payload has the latest timestamp, preserving
  /// sync metadata from the chosen event.
  static LocalFirstEvent<T> newestBy<T>(
    LocalFirstEvent<T> local,
    LocalFirstEvent<T> remote, {
    required DateTime Function(T payload) getUpdatedAt,
  }) {
    final localUpdated = getUpdatedAt(local.payload);
    final remoteUpdated = getUpdatedAt(remote.payload);

    if (remoteUpdated.isAfter(localUpdated)) {
      return remote.copyWith(
        repositoryName: remote.repositoryName.isEmpty
            ? local.repositoryName
            : remote.repositoryName,
        syncCreatedAt: remote.syncCreatedAt ?? local.syncCreatedAt,
      );
    }

    return local.copyWith(
      repositoryName: local.repositoryName.isEmpty
          ? remote.repositoryName
          : local.repositoryName,
      syncCreatedAt: local.syncCreatedAt ?? remote.syncCreatedAt,
    );
  }
}
