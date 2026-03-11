import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:local_first/local_first.dart';

/// Google Drive backup provider using the App Data folder.
///
/// Backups are stored in the hidden App Data folder, which is only accessible
/// by this application. The user won't see these files in their Google Drive.
///
/// Call [signIn] before using any other method.
class GDriveBackupProvider implements BackupStorageProvider {
  GoogleSignIn? _googleSignIn;
  drive.DriveApi? _driveApi;

  /// The folder name within App Data where backups are stored.
  final String folderName;

  /// Creates a [GDriveBackupProvider].
  ///
  /// - [folderName]: Optional subfolder name within App Data (default: `local_first_backups`).
  /// - [driveApi]: Optional [drive.DriveApi] for testing. If provided, [signIn]
  ///   is not required.
  GDriveBackupProvider({
    this.folderName = 'local_first_backups',
    @visibleForTesting drive.DriveApi? driveApi,
  }) : _driveApi = driveApi;

  /// Signs in with Google and initializes the Drive API.
  ///
  /// Must be called before any other method. Requests the `drive.appdata`
  /// scope for App Data folder access.
  Future<void> signIn() async {
    _googleSignIn = GoogleSignIn(scopes: [
      drive.DriveApi.driveAppdataScope,
    ]);

    final account = await _googleSignIn!.signIn();
    if (account == null) {
      throw StateError('Google Sign-In was cancelled by the user.');
    }

    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    _driveApi = drive.DriveApi(client);
  }

  /// Signs out and clears the Drive API.
  Future<void> signOut() async {
    await _googleSignIn?.signOut();
    _driveApi = null;
    _googleSignIn = null;
  }

  drive.DriveApi get _api {
    final api = _driveApi;
    if (api == null) {
      throw StateError(
        'GDriveBackupProvider not signed in. Call signIn() first.',
      );
    }
    return api;
  }

  @override
  Future<BackupMetadata> upload({
    required String fileName,
    required List<int> data,
  }) async {
    final media = drive.Media(
      Stream.value(data),
      data.length,
    );

    final driveFile = drive.File()
      ..name = fileName
      ..parents = ['appDataFolder'];

    final created = await _api.files.create(
      driveFile,
      uploadMedia: media,
    );

    return BackupMetadata(
      id: created.id!,
      fileName: fileName,
      createdAt: created.createdTime ?? DateTime.now().toUtc(),
      sizeInBytes: data.length,
      extra: {'mimeType': created.mimeType},
    );
  }

  @override
  Future<List<int>> download(BackupMetadata metadata) async {
    final response = await _api.files.get(
      metadata.id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is! drive.Media) {
      throw StateError('Failed to download backup: unexpected response type');
    }

    final bytes = <int>[];
    await response.stream.forEach(bytes.addAll);
    return bytes;
  }

  @override
  Future<List<BackupMetadata>> listBackups() async {
    final fileList = await _api.files.list(
      spaces: 'appDataFolder',
      orderBy: 'createdTime desc',
      $fields: 'files(id, name, createdTime, size)',
    );

    return (fileList.files ?? []).map((f) {
      return BackupMetadata(
        id: f.id!,
        fileName: f.name ?? 'unknown',
        createdAt: f.createdTime ?? DateTime.now().toUtc(),
        sizeInBytes: int.tryParse(f.size ?? '0') ?? 0,
      );
    }).toList();
  }

  @override
  Future<void> delete(BackupMetadata metadata) async {
    await _api.files.delete(metadata.id);
  }
}

/// HTTP client that injects Google auth headers into every request.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
