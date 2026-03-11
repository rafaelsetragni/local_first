import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:local_first/local_first.dart';

/// Firebase Storage backup provider.
///
/// Stores encrypted backup files under `backups/{uid}/` in Firebase Cloud
/// Storage. Requires an authenticated Firebase user.
///
/// Files are stored at: `backups/{uid}/{subfolder}/{fileName}`
class FirebaseBackupProvider implements BackupStorageProvider {
  /// Firebase Storage instance (lazy — resolved on first use).
  final FirebaseStorage? _storageOverride;

  /// Firebase Auth instance (lazy — resolved on first use).
  final FirebaseAuth? _authOverride;

  /// Subdirectory within the user's backup folder.
  final String subfolder;

  /// Creates a [FirebaseBackupProvider].
  ///
  /// - [storage]: Custom Firebase Storage instance (optional, defaults to
  ///   [FirebaseStorage.instance] on first use).
  /// - [auth]: Custom Firebase Auth instance (optional, defaults to
  ///   [FirebaseAuth.instance] on first use).
  /// - [subfolder]: Subdirectory name for backups (default: `local_first_backups`).
  FirebaseBackupProvider({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    this.subfolder = 'local_first_backups',
  }) : _storageOverride = storage,
       _authOverride = auth;

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'FirebaseBackupProvider requires an authenticated user. '
        'Sign in via Firebase Auth first.',
      );
    }
    return user.uid;
  }

  Reference _fileRef(String fileName) =>
      _storage.ref('backups/$_uid/$subfolder/$fileName');

  @override
  Future<BackupMetadata> upload({
    required String fileName,
    required List<int> data,
  }) async {
    final ref = _fileRef(fileName);
    await ref.putData(
      Uint8List.fromList(data),
      SettableMetadata(
        contentType: 'application/octet-stream',
        customMetadata: {'createdAt': DateTime.now().toUtc().toIso8601String()},
      ),
    );

    final metadata = await ref.getMetadata();

    return BackupMetadata(
      id: ref.fullPath,
      fileName: fileName,
      createdAt: metadata.timeCreated ?? DateTime.now().toUtc(),
      sizeInBytes: metadata.size ?? data.length,
    );
  }

  @override
  Future<List<int>> download(BackupMetadata metadata) async {
    final ref = _storage.ref(metadata.id);

    // Firebase Storage getData has a max size — use 100MB as limit
    const maxSize = 100 * 1024 * 1024;
    final data = await ref.getData(maxSize);

    if (data == null) {
      throw StateError('Failed to download backup: ${metadata.fileName}');
    }

    return data.toList();
  }

  @override
  Future<List<BackupMetadata>> listBackups() async {
    final prefix = _storage.ref('backups/$_uid/$subfolder');
    final result = await prefix.listAll();

    final backups = <BackupMetadata>[];
    for (final ref in result.items) {
      try {
        final metadata = await ref.getMetadata();
        backups.add(
          BackupMetadata(
            id: ref.fullPath,
            fileName: ref.name,
            createdAt: metadata.timeCreated ?? DateTime.now().toUtc(),
            sizeInBytes: metadata.size ?? 0,
          ),
        );
      } catch (_) {
        // Skip files that can't be read
      }
    }

    // Sort newest first
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  @override
  Future<void> delete(BackupMetadata metadata) async {
    await _storage.ref(metadata.id).delete();
  }
}
