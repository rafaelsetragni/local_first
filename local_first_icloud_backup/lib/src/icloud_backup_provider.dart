import 'dart:io';

import 'package:icloud_storage/icloud_storage.dart';
import 'package:local_first/local_first.dart';
import 'package:path/path.dart' as p;

/// iCloud backup provider using iCloud Documents.
///
/// Stores encrypted backup files in the app's iCloud container.
/// Only available on iOS and macOS — throws [UnsupportedError] on other
/// platforms.
///
/// Call with a valid [containerId] matching your Xcode iCloud entitlement.
class ICloudBackupProvider implements BackupStorageProvider {
  /// The iCloud container identifier (e.g. `iCloud.com.example.myapp`).
  final String containerId;

  /// Subdirectory within the iCloud container for backups.
  final String subfolder;

  /// Creates an [ICloudBackupProvider].
  ///
  /// - [containerId]: Your iCloud container ID from Xcode entitlements.
  /// - [subfolder]: Subdirectory name for backups (default: `local_first_backups`).
  ICloudBackupProvider({
    required this.containerId,
    this.subfolder = 'local_first_backups',
  }) {
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError(
        'ICloudBackupProvider is only available on iOS and macOS.',
      );
    }
  }

  String _relativePath(String fileName) => '$subfolder/$fileName';

  @override
  Future<BackupMetadata> upload({
    required String fileName,
    required List<int> data,
  }) async {
    // Write to a temporary file first, then upload to iCloud
    final tempDir = await Directory.systemTemp.createTemp('lfbk_');
    final tempFile = File(p.join(tempDir.path, fileName));
    await tempFile.writeAsBytes(data);

    try {
      await ICloudStorage.upload(
        containerId: containerId,
        filePath: tempFile.path,
        destinationRelativePath: _relativePath(fileName),
      );
    } finally {
      // Clean up temp file
      await tempDir.delete(recursive: true);
    }

    return BackupMetadata(
      id: _relativePath(fileName),
      fileName: fileName,
      createdAt: DateTime.now().toUtc(),
      sizeInBytes: data.length,
    );
  }

  @override
  Future<List<int>> download(BackupMetadata metadata) async {
    final tempDir = await Directory.systemTemp.createTemp('lfbk_dl_');
    final tempFile = File(p.join(tempDir.path, metadata.fileName));

    try {
      await ICloudStorage.download(
        containerId: containerId,
        relativePath: metadata.id,
        destinationFilePath: tempFile.path,
      );

      return await tempFile.readAsBytes();
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  @override
  Future<List<BackupMetadata>> listBackups() async {
    final files = await ICloudStorage.gather(
      containerId: containerId,
    );

    final backups = files
        .where((f) => f.relativePath.startsWith(subfolder))
        .map((f) => BackupMetadata(
              id: f.relativePath,
              fileName: p.basename(f.relativePath),
              createdAt: f.contentChangeDate,
              sizeInBytes: f.sizeInBytes,
            ))
        .toList();

    // Sort newest first
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  @override
  Future<void> delete(BackupMetadata metadata) async {
    await ICloudStorage.delete(
      containerId: containerId,
      relativePath: metadata.id,
    );
  }
}
