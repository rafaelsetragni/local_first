part of '../../local_first.dart';

// backup_storage_provider.dart and backup_crypto.dart are standalone libraries
// imported via the main local_first.dart barrel file.

/// Orchestrates backup creation and restoration for a [LocalFirstClient].
///
/// Uses a [BackupStorageProvider] to upload/download encrypted backup files
/// and [BackupCrypto] for AES-256 encryption with a user-supplied password.
///
/// Example:
/// ```dart
/// final backupService = BackupService(client: myClient);
///
/// // Create backup
/// final metadata = await backupService.createBackup(
///   provider: myGDriveProvider,
///   password: 'user-chosen-password',
/// );
///
/// // Restore backup (incremental — merges without duplicating)
/// await backupService.restoreBackup(
///   provider: myGDriveProvider,
///   metadata: metadata,
///   password: 'user-chosen-password',
/// );
/// ```
class BackupService {
  static const _logTag = 'BackupService';

  final LocalFirstClient client;

  BackupService({required this.client});

  /// Creates a full backup, encrypts it, and uploads to [provider].
  ///
  /// Captures all repository state (data + event log) and config values.
  /// The backup is compressed with gzip and encrypted with AES-256 using
  /// the given [password].
  Future<BackupMetadata> createBackup({
    required BackupStorageProvider provider,
    required String password,
  }) async {
    await client.awaitInitialization;

    // Collect repository data
    final repositories = <BackupRepositoryData>[];
    for (final repo in client._repositories) {
      final stateRows = await client._localStorage.getAll(repo.name);
      final eventRows = await client._localStorage.getAllEvents(repo.name);
      repositories.add(BackupRepositoryData(
        repositoryName: repo.name,
        stateRows: stateRows,
        eventRows: eventRows,
      ));
    }

    // Collect config
    final configKeys = await client._configStorage.getConfigKeys();
    final config = <String, Object>{};
    for (final key in configKeys) {
      final value = await client._configStorage.getConfigValue<Object>(key);
      if (value != null) {
        config[key] = value;
      }
    }

    final backupData = BackupData(
      version: BackupData.currentVersion,
      createdAt: DateTime.now().toUtc(),
      repositories: repositories,
      config: config,
    );

    // Encrypt
    final encryptedBytes = BackupCrypto.encryptJson(
      backupData.toJson(),
      password,
    );

    // Upload
    final timestamp = backupData.createdAt.toIso8601String()
        .replaceAll(':', '-');
    final fileName = 'backup_$timestamp.lfbk';

    final metadata = await provider.upload(
      fileName: fileName,
      data: encryptedBytes,
    );

    LocalFirstLogger.log(
      'Backup created: ${metadata.fileName} '
      '(${metadata.sizeInBytes} bytes, '
      '${repositories.length} repositories)',
      name: _logTag,
    );

    return metadata;
  }

  /// Downloads, decrypts, and incrementally restores a backup.
  ///
  /// Uses [LocalFirstClient.pullChanges] for each repository, which
  /// automatically deduplicates events that already exist locally.
  /// Config values are restored via [ConfigKeyValueStorage.setConfigValue].
  Future<void> restoreBackup({
    required BackupStorageProvider provider,
    required BackupMetadata metadata,
    required String password,
  }) async {
    await client.awaitInitialization;

    // Download and decrypt
    final cipherBytes = await provider.download(metadata);
    final json = BackupCrypto.decryptJson(cipherBytes, password);
    final backupData = BackupData.fromJson(json);

    LocalFirstLogger.log(
      'Restoring backup v${backupData.version} from '
      '${backupData.createdAt.toIso8601String()} '
      '(${backupData.repositories.length} repositories)',
      name: _logTag,
    );

    // Restore config values
    for (final entry in backupData.config.entries) {
      await client._configStorage.setConfigValue(entry.key, entry.value);
    }

    // Restore each repository via pullChanges (incremental merge)
    for (final repoData in backupData.repositories) {
      final repoName = repoData.repositoryName;

      // Check if this repository exists in the client
      try {
        client.getRepositoryByName(repoName);
      } catch (_) {
        LocalFirstLogger.log(
          'Skipping unknown repository "$repoName" during restore',
          name: _logTag,
        );
        continue;
      }

      // Convert local storage events to remote format for pullChanges
      final remoteEvents = _convertEventsToRemoteFormat(
        repoData.eventRows,
        repoData.stateRows,
      );

      if (remoteEvents.isNotEmpty) {
        await client.pullChanges(
          repositoryName: repoName,
          changes: remoteEvents,
        );
      }

      LocalFirstLogger.log(
        'Restored "$repoName": ${remoteEvents.length} events',
        name: _logTag,
      );
    }

    LocalFirstLogger.log('Backup restore complete', name: _logTag);
  }

  /// Lists available backups from the given [provider].
  Future<List<BackupMetadata>> listBackups(
    BackupStorageProvider provider,
  ) async {
    return provider.listBackups();
  }

  /// Deletes a backup from the given [provider].
  Future<void> deleteBackup({
    required BackupStorageProvider provider,
    required BackupMetadata metadata,
  }) async {
    await provider.delete(metadata);
    LocalFirstLogger.log(
      'Deleted backup: ${metadata.fileName}',
      name: _logTag,
    );
  }

  /// Converts local storage event rows into the remote JSON format
  /// expected by [LocalFirstClient.pullChanges].
  ///
  /// Local format uses int indexes for operation and millisecond epochs
  /// for timestamps. Remote format uses the same int indexes (supported by
  /// [LocalFirstEvent.fromRemoteJson]) but ISO 8601 strings for timestamps,
  /// and wraps entity data in the `_data` field.
  List<JsonMap> _convertEventsToRemoteFormat(
    List<JsonMap> eventRows,
    List<JsonMap> stateRows,
  ) {
    // Build a lookup from data_id to state data
    final stateById = <String, JsonMap>{};
    for (final row in stateRows) {
      // Try common id field names
      final id = row[LocalFirstEvent.kDataId] as String? ??
          row['id'] as String? ??
          row['_id'] as String?;
      if (id != null) {
        stateById[id] = row;
      }
    }

    final remoteEvents = <JsonMap>[];
    for (final event in eventRows) {
      final eventId = event[LocalFirstEvent.kEventId] as String?;
      final opIndex = event[LocalFirstEvent.kOperation];
      final createdAt = event[LocalFirstEvent.kSyncCreatedAt];
      final dataId = event[LocalFirstEvent.kDataId] as String?;

      if (eventId == null || opIndex == null || createdAt == null) continue;

      // Convert timestamp to ISO 8601
      final String createdAtStr;
      if (createdAt is int) {
        createdAtStr = DateTime.fromMillisecondsSinceEpoch(
          createdAt,
          isUtc: true,
        ).toIso8601String();
      } else if (createdAt is String) {
        createdAtStr = createdAt;
      } else {
        continue;
      }

      final remoteEvent = <String, dynamic>{
        LocalFirstEvent.kEventId: eventId,
        LocalFirstEvent.kOperation: opIndex,
        LocalFirstEvent.kSyncCreatedAt: createdAtStr,
        if (dataId != null) LocalFirstEvent.kDataId: dataId,
      };

      // For insert/update, attach state data
      final op = opIndex is int && opIndex < SyncOperation.values.length
          ? SyncOperation.values[opIndex]
          : null;
      if (op != null && op != SyncOperation.delete && dataId != null) {
        final stateData = stateById[dataId];
        if (stateData != null) {
          // Strip metadata keys from state data for the _data field
          final cleanData = Map<String, dynamic>.from(stateData)
            ..remove(LocalFirstEvent.kEventId)
            ..remove(LocalFirstEvent.kDataId)
            ..remove(LocalFirstEvent.kSyncStatus)
            ..remove(LocalFirstEvent.kOperation)
            ..remove(LocalFirstEvent.kSyncCreatedAt)
            ..remove(LocalFirstEvent.kLastEventId);
          remoteEvent[LocalFirstEvent.kData] = cleanData;
        }
      }

      remoteEvents.add(remoteEvent);
    }

    return remoteEvents;
  }
}
