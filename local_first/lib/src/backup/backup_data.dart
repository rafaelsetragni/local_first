part of '../../local_first.dart';

/// Data for a single repository included in a backup.
class BackupRepositoryData {
  /// The repository name (matches [LocalFirstRepository.name]).
  final String repositoryName;

  /// State table rows from [LocalFirstStorage.getAll].
  final List<JsonMap> stateRows;

  /// Event log rows from [LocalFirstStorage.getAllEvents].
  final List<JsonMap> eventRows;

  const BackupRepositoryData({
    required this.repositoryName,
    required this.stateRows,
    required this.eventRows,
  });

  Map<String, dynamic> toJson() => {
    'repositoryName': repositoryName,
    'stateRows': stateRows,
    'eventRows': eventRows,
  };

  factory BackupRepositoryData.fromJson(Map<String, dynamic> json) {
    return BackupRepositoryData(
      repositoryName: json['repositoryName'] as String,
      stateRows: (json['stateRows'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      eventRows: (json['eventRows'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}

/// Complete backup payload containing all application state.
///
/// This model captures the full state of a [LocalFirstClient] at a point in
/// time: all repository data (state + event log) and config key/value pairs.
class BackupData {
  /// Schema version for forward compatibility.
  static const int currentVersion = 1;

  /// Backup format version.
  final int version;

  /// When the backup was created.
  final DateTime createdAt;

  /// Active namespace at backup time (if any).
  final String? namespace;

  /// Data for each repository.
  final List<BackupRepositoryData> repositories;

  /// All config key/value pairs.
  final Map<String, Object> config;

  const BackupData({
    required this.version,
    required this.createdAt,
    this.namespace,
    required this.repositories,
    required this.config,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (namespace != null) 'namespace': namespace,
    'repositories': repositories.map((r) => r.toJson()).toList(),
    'config': config,
  };

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      version: json['version'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      namespace: json['namespace'] as String?,
      repositories: (json['repositories'] as List)
          .map((e) => BackupRepositoryData.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
      config: Map<String, Object>.from(json['config'] as Map),
    );
  }
}
