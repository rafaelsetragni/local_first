/// Metadata about a stored backup file.
///
/// Each [BackupStorageProvider] returns instances of this class to describe
/// available backups. The [id] is provider-specific (e.g., a Google Drive file
/// id, an iCloud record name, or a Firebase Storage path).
class BackupMetadata {
  /// Provider-specific unique identifier for the backup.
  final String id;

  /// File name used when storing the backup (e.g. `backup_2026-03-06T12:00:00Z.lfbk`).
  final String fileName;

  /// When the backup was created.
  final DateTime createdAt;

  /// Size of the backup file in bytes.
  final int sizeInBytes;

  /// Optional provider-specific metadata (e.g., Drive file metadata, iCloud
  /// container info, etc.).
  final Map<String, dynamic>? extra;

  const BackupMetadata({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.sizeInBytes,
    this.extra,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'sizeInBytes': sizeInBytes,
    if (extra != null) 'extra': extra,
  };

  factory BackupMetadata.fromJson(Map<String, dynamic> json) => BackupMetadata(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    sizeInBytes: json['sizeInBytes'] as int,
    extra: json['extra'] as Map<String, dynamic>?,
  );
}

/// Abstract interface for cloud backup storage providers.
///
/// Implement this interface to support different cloud storage backends
/// (Google Drive, iCloud, Firebase Storage, etc.). Each provider lives in
/// its own package for modularity.
///
/// Example:
/// ```dart
/// class MyCloudProvider implements BackupStorageProvider {
///   @override
///   Future<BackupMetadata> upload({
///     required String fileName,
///     required List<int> data,
///   }) async {
///     // Upload to your cloud storage
///   }
///   // ...
/// }
/// ```
abstract class BackupStorageProvider {
  /// Uploads encrypted backup bytes to cloud storage.
  ///
  /// Returns [BackupMetadata] describing the stored backup.
  Future<BackupMetadata> upload({
    required String fileName,
    required List<int> data,
  });

  /// Downloads backup bytes from cloud storage.
  Future<List<int>> download(BackupMetadata metadata);

  /// Lists available backups, newest first.
  Future<List<BackupMetadata>> listBackups();

  /// Deletes a backup from cloud storage.
  Future<void> delete(BackupMetadata metadata);
}
