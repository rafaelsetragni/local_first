import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:local_first/local_first.dart';
import 'package:local_first_gdrive_backup/local_first_gdrive_backup.dart';
import 'package:mocktail/mocktail.dart';

// --- Mocks ---

class MockDriveApi extends Mock implements drive.DriveApi {}

class MockFilesResource extends Mock implements drive.FilesResource {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockHttpClient extends Mock implements http.Client {}

// --- Helpers ---

class FakeDriveFile extends Fake implements drive.File {}

class FakeMedia extends Fake implements drive.Media {}

class _FakeBaseRequest extends Fake implements http.BaseRequest {
  @override
  final Map<String, String> headers = {};
}

void main() {
  late MockDriveApi mockDriveApi;
  late MockFilesResource mockFiles;
  late GDriveBackupProvider provider;

  setUpAll(() {
    registerFallbackValue(FakeDriveFile());
    registerFallbackValue(FakeMedia());
    registerFallbackValue(drive.DownloadOptions.fullMedia);
    registerFallbackValue(_FakeBaseRequest());
  });

  setUp(() {
    mockDriveApi = MockDriveApi();
    mockFiles = MockFilesResource();

    when(() => mockDriveApi.files).thenReturn(mockFiles);

    provider = GDriveBackupProvider(driveApi: mockDriveApi);
  });

  group('GDriveBackupProvider', () {
    test('default folder name is local_first_backups', () {
      final p = GDriveBackupProvider();
      expect(p.folderName, equals('local_first_backups'));
    });

    test('accepts custom folder name', () {
      final p = GDriveBackupProvider(folderName: 'my_backups');
      expect(p.folderName, equals('my_backups'));
    });

    group('_api', () {
      test('throws StateError when not signed in', () {
        final p = GDriveBackupProvider();

        expect(
          () => p.upload(fileName: 'test.lfbk', data: [1]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('not signed in'),
            ),
          ),
        );
      });

      test('throws StateError for listBackups when not signed in', () {
        final p = GDriveBackupProvider();
        expect(() => p.listBackups(), throwsA(isA<StateError>()));
      });

      test('throws StateError for download when not signed in', () {
        final p = GDriveBackupProvider();
        final metadata = BackupMetadata(
          id: 'id',
          fileName: 'f.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 0,
        );
        expect(() => p.download(metadata), throwsA(isA<StateError>()));
      });

      test('throws StateError for delete when not signed in', () {
        final p = GDriveBackupProvider();
        final metadata = BackupMetadata(
          id: 'id',
          fileName: 'f.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 0,
        );
        expect(() => p.delete(metadata), throwsA(isA<StateError>()));
      });
    });

    group('upload', () {
      test('creates file in appDataFolder and returns metadata', () async {
        final now = DateTime.utc(2026, 3, 9, 12);
        final createdFile = drive.File()
          ..id = 'file-id-123'
          ..name = 'test.lfbk'
          ..createdTime = now
          ..mimeType = 'application/octet-stream';

        when(
          () => mockFiles.create(any(), uploadMedia: any(named: 'uploadMedia')),
        ).thenAnswer((_) async => createdFile);

        final result = await provider.upload(
          fileName: 'test.lfbk',
          data: [1, 2, 3],
        );

        expect(result.id, equals('file-id-123'));
        expect(result.fileName, equals('test.lfbk'));
        expect(result.createdAt, equals(now));
        expect(result.sizeInBytes, equals(3));
        expect(result.extra, equals({'mimeType': 'application/octet-stream'}));

        final captured =
            verify(
                  () => mockFiles.create(
                    captureAny(),
                    uploadMedia: any(named: 'uploadMedia'),
                  ),
                ).captured.single
                as drive.File;
        expect(captured.parents, equals(['appDataFolder']));
        expect(captured.name, equals('test.lfbk'));
      });

      test('uses fallback createdAt when createdTime is null', () async {
        final createdFile = drive.File()
          ..id = 'file-id'
          ..name = 'test.lfbk'
          ..createdTime = null
          ..mimeType = null;

        when(
          () => mockFiles.create(any(), uploadMedia: any(named: 'uploadMedia')),
        ).thenAnswer((_) async => createdFile);

        final result = await provider.upload(
          fileName: 'test.lfbk',
          data: [10, 20],
        );

        expect(result.id, equals('file-id'));
        expect(result.createdAt, isNotNull);
        expect(result.sizeInBytes, equals(2));
      });
    });

    group('download', () {
      test('downloads file and returns bytes', () async {
        final mediaStream = Stream<List<int>>.fromIterable([
          [1, 2, 3],
          [4, 5, 6],
        ]);
        final media = drive.Media(mediaStream, 6);

        when(
          () => mockFiles.get(
            any(),
            downloadOptions: drive.DownloadOptions.fullMedia,
          ),
        ).thenAnswer((_) async => media);

        final metadata = BackupMetadata(
          id: 'file-id-123',
          fileName: 'test.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 6,
        );

        final result = await provider.download(metadata);

        expect(result, equals([1, 2, 3, 4, 5, 6]));
        verify(
          () => mockFiles.get(
            'file-id-123',
            downloadOptions: drive.DownloadOptions.fullMedia,
          ),
        ).called(1);
      });

      test('throws StateError when response is not Media', () async {
        when(
          () => mockFiles.get(
            any(),
            downloadOptions: drive.DownloadOptions.fullMedia,
          ),
        ).thenAnswer((_) async => drive.File());

        final metadata = BackupMetadata(
          id: 'file-id',
          fileName: 'test.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 0,
        );

        expect(
          () => provider.download(metadata),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('unexpected response type'),
            ),
          ),
        );
      });
    });

    group('listBackups', () {
      test('returns backups from file list', () async {
        final now = DateTime.utc(2026, 3, 9);
        final earlier = DateTime.utc(2026, 3, 1);

        final fileList = drive.FileList()
          ..files = [
            drive.File()
              ..id = 'id-1'
              ..name = 'backup1.lfbk'
              ..createdTime = now
              ..size = '1024',
            drive.File()
              ..id = 'id-2'
              ..name = 'backup2.lfbk'
              ..createdTime = earlier
              ..size = '512',
          ];

        when(
          () => mockFiles.list(
            spaces: any(named: 'spaces'),
            orderBy: any(named: 'orderBy'),
            $fields: any(named: '\$fields'),
          ),
        ).thenAnswer((_) async => fileList);

        final backups = await provider.listBackups();

        expect(backups.length, equals(2));
        expect(backups[0].id, equals('id-1'));
        expect(backups[0].fileName, equals('backup1.lfbk'));
        expect(backups[0].createdAt, equals(now));
        expect(backups[0].sizeInBytes, equals(1024));
        expect(backups[1].id, equals('id-2'));
        expect(backups[1].sizeInBytes, equals(512));

        verify(
          () => mockFiles.list(
            spaces: 'appDataFolder',
            orderBy: 'createdTime desc',
            $fields: 'files(id, name, createdTime, size)',
          ),
        ).called(1);
      });

      test('returns empty list when files is null', () async {
        final fileList = drive.FileList()..files = null;

        when(
          () => mockFiles.list(
            spaces: any(named: 'spaces'),
            orderBy: any(named: 'orderBy'),
            $fields: any(named: '\$fields'),
          ),
        ).thenAnswer((_) async => fileList);

        final backups = await provider.listBackups();
        expect(backups, isEmpty);
      });

      test('uses fallback values when file fields are null', () async {
        final fileList = drive.FileList()
          ..files = [
            drive.File()
              ..id = 'id-1'
              ..name = null
              ..createdTime = null
              ..size = null,
          ];

        when(
          () => mockFiles.list(
            spaces: any(named: 'spaces'),
            orderBy: any(named: 'orderBy'),
            $fields: any(named: '\$fields'),
          ),
        ).thenAnswer((_) async => fileList);

        final backups = await provider.listBackups();

        expect(backups.length, equals(1));
        expect(backups[0].fileName, equals('unknown'));
        expect(backups[0].createdAt, isNotNull);
        expect(backups[0].sizeInBytes, equals(0));
      });

      test('handles invalid size string gracefully', () async {
        final fileList = drive.FileList()
          ..files = [
            drive.File()
              ..id = 'id-1'
              ..name = 'f.lfbk'
              ..createdTime = DateTime.utc(2026)
              ..size = 'not-a-number',
          ];

        when(
          () => mockFiles.list(
            spaces: any(named: 'spaces'),
            orderBy: any(named: 'orderBy'),
            $fields: any(named: '\$fields'),
          ),
        ).thenAnswer((_) async => fileList);

        final backups = await provider.listBackups();

        expect(backups[0].sizeInBytes, equals(0));
      });
    });

    group('delete', () {
      test('deletes file by metadata id', () async {
        when(() => mockFiles.delete(any())).thenAnswer((_) async {});

        final metadata = BackupMetadata(
          id: 'file-id-to-delete',
          fileName: 'old.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 100,
        );

        await provider.delete(metadata);

        verify(() => mockFiles.delete('file-id-to-delete')).called(1);
      });
    });

    group('signOut', () {
      test('clears driveApi making provider unusable', () async {
        // Provider starts with injected driveApi, signOut clears it
        await provider.signOut();

        expect(
          () => provider.upload(fileName: 'test.lfbk', data: [1]),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('signIn', () {
      test('initializes driveApi after successful sign-in', () async {
        final mockSignIn = MockGoogleSignIn();
        final mockAccount = MockGoogleSignInAccount();

        when(() => mockSignIn.signIn()).thenAnswer((_) async => mockAccount);
        when(
          () => mockAccount.authHeaders,
        ).thenAnswer((_) async => {'Authorization': 'Bearer test-token'});

        final p = GDriveBackupProvider(googleSignIn: mockSignIn);
        await p.signIn();

        verify(() => mockSignIn.signIn()).called(1);
        verify(() => mockAccount.authHeaders).called(1);
        // Provider is now usable — upload would not throw StateError
        // (it would throw because DriveApi hits the network, not because of missing auth)
      });

      test('throws StateError when user cancels sign-in', () async {
        final mockSignIn = MockGoogleSignIn();
        when(() => mockSignIn.signIn()).thenAnswer((_) async => null);

        final p = GDriveBackupProvider(googleSignIn: mockSignIn);

        await expectLater(
          p.signIn(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('cancelled'),
            ),
          ),
        );
      });
    });
  });

  group('GoogleAuthClient', () {
    test('adds auth headers to outgoing requests', () async {
      final mockInner = MockHttpClient();
      final authClient = GoogleAuthClient(
        {'Authorization': 'Bearer test-token', 'X-Custom': 'value'},
        inner: mockInner,
      );

      final request = http.Request('GET', Uri.parse('https://example.com'));
      final response = http.StreamedResponse(const Stream.empty(), 200);

      when(() => mockInner.send(any())).thenAnswer((_) async => response);

      await authClient.send(request);

      expect(request.headers['Authorization'], equals('Bearer test-token'));
      expect(request.headers['X-Custom'], equals('value'));
      verify(() => mockInner.send(request)).called(1);
    });
  });
}
