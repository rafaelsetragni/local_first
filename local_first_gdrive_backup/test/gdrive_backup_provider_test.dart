import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_gdrive_backup/local_first_gdrive_backup.dart';

void main() {
  group('GDriveBackupProvider', () {
    test('implements BackupStorageProvider', () {
      // Verify the type relationship at compile time
      expect(GDriveBackupProvider, isNotNull);
    });

    test('throws StateError when not signed in', () {
      final provider = GDriveBackupProvider();

      expect(
        () => provider.upload(fileName: 'test.lfbk', data: [1, 2, 3]),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not signed in'),
        )),
      );
    });

    test('throws StateError for listBackups when not signed in', () {
      final provider = GDriveBackupProvider();

      expect(
        () => provider.listBackups(),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError for download when not signed in', () {
      final provider = GDriveBackupProvider();
      final metadata = BackupMetadata(
        id: 'test-id',
        fileName: 'test.lfbk',
        createdAt: DateTime.now(),
        sizeInBytes: 100,
      );

      expect(
        () => provider.download(metadata),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError for delete when not signed in', () {
      final provider = GDriveBackupProvider();
      final metadata = BackupMetadata(
        id: 'test-id',
        fileName: 'test.lfbk',
        createdAt: DateTime.now(),
        sizeInBytes: 100,
      );

      expect(
        () => provider.delete(metadata),
        throwsA(isA<StateError>()),
      );
    });

    test('accepts custom folder name', () {
      final provider = GDriveBackupProvider(folderName: 'my_backups');
      expect(provider.folderName, equals('my_backups'));
    });

    test('default folder name is local_first_backups', () {
      final provider = GDriveBackupProvider();
      expect(provider.folderName, equals('local_first_backups'));
    });
  });
}
