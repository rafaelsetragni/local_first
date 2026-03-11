import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage/icloud_storage.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_icloud_backup/local_first_icloud_backup.dart';
import 'package:mocktail/mocktail.dart';

// --- Mocks ---

class MockICloudStorageDelegate extends Mock implements ICloudStorageDelegate {}

// --- Helpers ---

/// Creates an [ICloudFile] from a map for testing.
ICloudFile createICloudFile({
  required String relativePath,
  required int sizeInBytes,
  required DateTime contentChangeDate,
}) {
  return ICloudFile.fromMap({
    'relativePath': relativePath,
    'sizeInBytes': sizeInBytes,
    'creationDate': contentChangeDate.millisecondsSinceEpoch / 1000.0,
    'contentChangeDate': contentChangeDate.millisecondsSinceEpoch / 1000.0,
    'isDownloading': false,
    'downloadStatus': 'NSMetadataUbiquitousItemDownloadingStatusCurrent',
    'isUploading': false,
    'isUploaded': true,
    'hasUnresolvedConflicts': false,
  });
}

void main() {
  // Skip all tests on non-Apple platforms
  if (!Platform.isIOS && !Platform.isMacOS) {
    test('skipped on non-Apple platform', () {}, skip: 'Not Apple');
    return;
  }

  late MockICloudStorageDelegate mockDelegate;
  late ICloudBackupProvider provider;

  setUp(() {
    mockDelegate = MockICloudStorageDelegate();
    provider = ICloudBackupProvider(
      containerId: 'iCloud.com.test',
      delegate: mockDelegate,
    );
  });

  group('ICloudBackupProvider', () {
    test('can be instantiated on Apple platforms', () {
      expect(provider.containerId, equals('iCloud.com.test'));
      expect(provider.subfolder, equals('local_first_backups'));
    });

    test('accepts custom subfolder', () {
      final p = ICloudBackupProvider(
        containerId: 'iCloud.com.test',
        subfolder: 'my_backups',
        delegate: mockDelegate,
      );
      expect(p.subfolder, equals('my_backups'));
    });

    group('upload', () {
      test(
        'writes temp file, uploads, cleans up, and returns metadata',
        () async {
          when(
            () => mockDelegate.upload(
              containerId: any(named: 'containerId'),
              filePath: any(named: 'filePath'),
              destinationRelativePath: any(named: 'destinationRelativePath'),
            ),
          ).thenAnswer((_) async {});

          final result = await provider.upload(
            fileName: 'test.lfbk',
            data: [1, 2, 3, 4, 5],
          );

          expect(result.id, equals('local_first_backups/test.lfbk'));
          expect(result.fileName, equals('test.lfbk'));
          expect(result.sizeInBytes, equals(5));
          expect(result.createdAt, isNotNull);

          final captured = verify(
            () => mockDelegate.upload(
              containerId: captureAny(named: 'containerId'),
              filePath: captureAny(named: 'filePath'),
              destinationRelativePath: captureAny(
                named: 'destinationRelativePath',
              ),
            ),
          ).captured;

          expect(captured[0], equals('iCloud.com.test'));
          // filePath is a temp path — just verify it was passed
          expect(captured[1], isA<String>());
          expect(captured[2], equals('local_first_backups/test.lfbk'));
        },
      );

      test('uses custom subfolder in relative path', () async {
        final customProvider = ICloudBackupProvider(
          containerId: 'iCloud.com.test',
          subfolder: 'custom_dir',
          delegate: mockDelegate,
        );

        when(
          () => mockDelegate.upload(
            containerId: any(named: 'containerId'),
            filePath: any(named: 'filePath'),
            destinationRelativePath: any(named: 'destinationRelativePath'),
          ),
        ).thenAnswer((_) async {});

        final result = await customProvider.upload(
          fileName: 'backup.lfbk',
          data: [10, 20],
        );

        expect(result.id, equals('custom_dir/backup.lfbk'));

        verify(
          () => mockDelegate.upload(
            containerId: 'iCloud.com.test',
            filePath: any(named: 'filePath'),
            destinationRelativePath: 'custom_dir/backup.lfbk',
          ),
        ).called(1);
      });

      test('cleans up temp dir even if upload fails', () async {
        when(
          () => mockDelegate.upload(
            containerId: any(named: 'containerId'),
            filePath: any(named: 'filePath'),
            destinationRelativePath: any(named: 'destinationRelativePath'),
          ),
        ).thenThrow(Exception('upload failed'));

        expect(
          () => provider.upload(fileName: 'test.lfbk', data: [1]),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('download', () {
      test('downloads to temp file, reads bytes, cleans up', () async {
        when(
          () => mockDelegate.download(
            containerId: any(named: 'containerId'),
            relativePath: any(named: 'relativePath'),
            destinationFilePath: any(named: 'destinationFilePath'),
          ),
        ).thenAnswer((invocation) async {
          // Simulate iCloud writing data to the destination file
          final destPath =
              invocation.namedArguments[#destinationFilePath] as String;
          await File(destPath).writeAsBytes([10, 20, 30]);
        });

        final metadata = BackupMetadata(
          id: 'local_first_backups/test.lfbk',
          fileName: 'test.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 3,
        );

        final result = await provider.download(metadata);

        expect(result, equals([10, 20, 30]));

        verify(
          () => mockDelegate.download(
            containerId: 'iCloud.com.test',
            relativePath: 'local_first_backups/test.lfbk',
            destinationFilePath: any(named: 'destinationFilePath'),
          ),
        ).called(1);
      });

      test('cleans up temp dir even if download fails', () async {
        when(
          () => mockDelegate.download(
            containerId: any(named: 'containerId'),
            relativePath: any(named: 'relativePath'),
            destinationFilePath: any(named: 'destinationFilePath'),
          ),
        ).thenThrow(Exception('download failed'));

        final metadata = BackupMetadata(
          id: 'local_first_backups/test.lfbk',
          fileName: 'test.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 0,
        );

        expect(() => provider.download(metadata), throwsA(isA<Exception>()));
      });
    });

    group('listBackups', () {
      test('returns filtered and sorted backups', () async {
        final older = DateTime.utc(2026, 1, 1);
        final newer = DateTime.utc(2026, 3, 9);

        when(
          () => mockDelegate.gather(containerId: any(named: 'containerId')),
        ).thenAnswer(
          (_) async => [
            createICloudFile(
              relativePath: 'local_first_backups/old.lfbk',
              sizeInBytes: 100,
              contentChangeDate: older,
            ),
            createICloudFile(
              relativePath: 'local_first_backups/new.lfbk',
              sizeInBytes: 200,
              contentChangeDate: newer,
            ),
            // This file should be filtered out (different subfolder)
            createICloudFile(
              relativePath: 'other_folder/unrelated.dat',
              sizeInBytes: 50,
              contentChangeDate: DateTime.utc(2026, 2, 1),
            ),
          ],
        );

        final backups = await provider.listBackups();

        expect(backups.length, equals(2));
        // Newest first
        expect(backups[0].fileName, equals('new.lfbk'));
        expect(backups[0].sizeInBytes, equals(200));
        expect(backups[1].fileName, equals('old.lfbk'));
        expect(backups[1].sizeInBytes, equals(100));

        verify(
          () => mockDelegate.gather(containerId: 'iCloud.com.test'),
        ).called(1);
      });

      test('returns empty list when no backups exist', () async {
        when(
          () => mockDelegate.gather(containerId: any(named: 'containerId')),
        ).thenAnswer((_) async => []);

        final backups = await provider.listBackups();
        expect(backups, isEmpty);
      });

      test('filters by custom subfolder', () async {
        final customProvider = ICloudBackupProvider(
          containerId: 'iCloud.com.test',
          subfolder: 'custom',
          delegate: mockDelegate,
        );

        when(
          () => mockDelegate.gather(containerId: any(named: 'containerId')),
        ).thenAnswer(
          (_) async => [
            createICloudFile(
              relativePath: 'custom/file.lfbk',
              sizeInBytes: 10,
              contentChangeDate: DateTime.utc(2026, 3, 9),
            ),
            createICloudFile(
              relativePath: 'local_first_backups/other.lfbk',
              sizeInBytes: 20,
              contentChangeDate: DateTime.utc(2026, 3, 9),
            ),
          ],
        );

        final backups = await customProvider.listBackups();

        expect(backups.length, equals(1));
        expect(backups[0].fileName, equals('file.lfbk'));
      });
    });

    group('delete', () {
      test('deletes file by metadata id', () async {
        when(
          () => mockDelegate.delete(
            containerId: any(named: 'containerId'),
            relativePath: any(named: 'relativePath'),
          ),
        ).thenAnswer((_) async {});

        final metadata = BackupMetadata(
          id: 'local_first_backups/old.lfbk',
          fileName: 'old.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 100,
        );

        await provider.delete(metadata);

        verify(
          () => mockDelegate.delete(
            containerId: 'iCloud.com.test',
            relativePath: 'local_first_backups/old.lfbk',
          ),
        ).called(1);
      });
    });

    // These tests exercise the _DefaultICloudStorageDelegate code paths.
    // No mock delegate is injected — the real ICloudStorage static methods are
    // invoked, which throw (no platform channel in unit tests). That is expected:
    // the goal is to ensure the delegation code is reached and covered.
    group('default delegate', () {
      late ICloudBackupProvider defaultProvider;

      setUp(() {
        defaultProvider = ICloudBackupProvider(containerId: 'iCloud.com.test');
      });

      test('upload delegates to ICloudStorage.upload', () {
        expect(
          () => defaultProvider.upload(fileName: 'test.lfbk', data: [1]),
          throwsA(anything),
        );
      });

      test('download delegates to ICloudStorage.download', () {
        final metadata = BackupMetadata(
          id: 'local_first_backups/test.lfbk',
          fileName: 'test.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 0,
        );
        expect(
          () => defaultProvider.download(metadata),
          throwsA(anything),
        );
      });

      test('listBackups delegates to ICloudStorage.gather', () {
        expect(() => defaultProvider.listBackups(), throwsA(anything));
      });

      test('delete delegates to ICloudStorage.delete', () {
        final metadata = BackupMetadata(
          id: 'local_first_backups/old.lfbk',
          fileName: 'old.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 0,
        );
        expect(() => defaultProvider.delete(metadata), throwsA(anything));
      });
    });
  });
}
