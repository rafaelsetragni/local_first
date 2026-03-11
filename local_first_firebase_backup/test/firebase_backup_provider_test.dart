import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_firebase_backup/local_first_firebase_backup.dart';
import 'package:mocktail/mocktail.dart';

// --- Mocks ---

class MockFirebaseStorage extends Mock implements FirebaseStorage {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockReference extends Mock implements Reference {}

class MockFullMetadata extends Mock implements FullMetadata {}

class MockListResult extends Mock implements ListResult {}

class MockTaskSnapshot extends Mock implements TaskSnapshot {}

// --- Helpers ---

/// Fake [SettableMetadata] for registerFallbackValue.
class FakeSettableMetadata extends Fake implements SettableMetadata {}

/// Fake [UploadTask] that completes immediately when awaited.
class FakeUploadTask extends Fake implements UploadTask {
  final TaskSnapshot _snapshot = MockTaskSnapshot();

  @override
  Future<S> then<S>(
    FutureOr<S> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => Future<TaskSnapshot>.value(_snapshot).then(onValue, onError: onError);

  @override
  Future<TaskSnapshot> whenComplete(FutureOr Function() action) =>
      Future<TaskSnapshot>.value(_snapshot).whenComplete(action);

  @override
  Future<TaskSnapshot> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => Future<TaskSnapshot>.value(_snapshot).catchError(onError, test: test);

  @override
  Stream<TaskSnapshot> asStream() => Stream.value(_snapshot);

  @override
  Future<TaskSnapshot> timeout(
    Duration timeLimit, {
    FutureOr<TaskSnapshot> Function()? onTimeout,
  }) => Future<TaskSnapshot>.value(
    _snapshot,
  ).timeout(timeLimit, onTimeout: onTimeout);
}

void main() {
  late MockFirebaseStorage mockStorage;
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late FirebaseBackupProvider provider;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(FakeSettableMetadata());
  });

  setUp(() {
    mockStorage = MockFirebaseStorage();
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();

    when(() => mockUser.uid).thenReturn('test-uid-123');
    when(() => mockAuth.currentUser).thenReturn(mockUser);

    provider = FirebaseBackupProvider(storage: mockStorage, auth: mockAuth);
  });

  group('FirebaseBackupProvider', () {
    test('default subfolder is local_first_backups', () {
      final p = FirebaseBackupProvider(storage: mockStorage, auth: mockAuth);
      expect(p.subfolder, equals('local_first_backups'));
    });

    test('accepts custom subfolder', () {
      final p = FirebaseBackupProvider(
        storage: mockStorage,
        auth: mockAuth,
        subfolder: 'my_backups',
      );
      expect(p.subfolder, equals('my_backups'));
    });

    group('upload', () {
      test('uploads data and returns metadata', () async {
        final mockRef = MockReference();
        final mockMetadata = MockFullMetadata();
        final now = DateTime.utc(2026, 3, 6, 12);

        when(() => mockStorage.ref(any())).thenReturn(mockRef);
        when(
          () => mockRef.putData(any(), any()),
        ).thenAnswer((_) => FakeUploadTask());
        when(() => mockRef.getMetadata()).thenAnswer((_) async => mockMetadata);
        when(
          () => mockRef.fullPath,
        ).thenReturn('backups/test-uid-123/local_first_backups/test.lfbk');
        when(() => mockMetadata.timeCreated).thenReturn(now);
        when(() => mockMetadata.size).thenReturn(42);

        final result = await provider.upload(
          fileName: 'test.lfbk',
          data: [1, 2, 3],
        );

        expect(
          result.id,
          equals('backups/test-uid-123/local_first_backups/test.lfbk'),
        );
        expect(result.fileName, equals('test.lfbk'));
        expect(result.createdAt, equals(now));
        expect(result.sizeInBytes, equals(42));

        verify(
          () => mockStorage.ref(
            'backups/test-uid-123/local_first_backups/test.lfbk',
          ),
        ).called(1);
        verify(() => mockRef.putData(any(), any())).called(1);
      });

      test('uses data.length when metadata.size is null', () async {
        final mockRef = MockReference();
        final mockMetadata = MockFullMetadata();

        when(() => mockStorage.ref(any())).thenReturn(mockRef);
        when(
          () => mockRef.putData(any(), any()),
        ).thenAnswer((_) => FakeUploadTask());
        when(() => mockRef.getMetadata()).thenAnswer((_) async => mockMetadata);
        when(() => mockRef.fullPath).thenReturn('path/file.lfbk');
        when(() => mockMetadata.timeCreated).thenReturn(null);
        when(() => mockMetadata.size).thenReturn(null);

        final result = await provider.upload(
          fileName: 'file.lfbk',
          data: [10, 20, 30, 40, 50],
        );

        expect(result.sizeInBytes, equals(5));
      });
    });

    group('download', () {
      test('downloads and returns bytes', () async {
        final mockRef = MockReference();
        final data = Uint8List.fromList([10, 20, 30]);

        when(() => mockStorage.ref(any())).thenReturn(mockRef);
        when(() => mockRef.getData(any())).thenAnswer((_) async => data);

        final metadata = BackupMetadata(
          id: 'backups/uid/folder/file.lfbk',
          fileName: 'file.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 3,
        );

        final result = await provider.download(metadata);

        expect(result, equals([10, 20, 30]));
        verify(() => mockStorage.ref('backups/uid/folder/file.lfbk')).called(1);
      });

      test('throws StateError when getData returns null', () async {
        final mockRef = MockReference();

        when(() => mockStorage.ref(any())).thenReturn(mockRef);
        when(() => mockRef.getData(any())).thenAnswer((_) async => null);

        final metadata = BackupMetadata(
          id: 'path/file.lfbk',
          fileName: 'file.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 0,
        );

        expect(
          () => provider.download(metadata),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Failed to download'),
            ),
          ),
        );
      });
    });

    group('listBackups', () {
      test('returns backups sorted newest first', () async {
        final prefixRef = MockReference();
        final ref1 = MockReference();
        final ref2 = MockReference();
        final meta1 = MockFullMetadata();
        final meta2 = MockFullMetadata();
        final listResult = MockListResult();

        final older = DateTime.utc(2026, 1, 1);
        final newer = DateTime.utc(2026, 3, 6);

        when(() => mockStorage.ref(any())).thenReturn(prefixRef);
        when(() => prefixRef.listAll()).thenAnswer((_) async => listResult);
        when(() => listResult.items).thenReturn([ref1, ref2]);

        when(() => ref1.getMetadata()).thenAnswer((_) async => meta1);
        when(() => ref1.fullPath).thenReturn('path/backup1.lfbk');
        when(() => ref1.name).thenReturn('backup1.lfbk');
        when(() => meta1.timeCreated).thenReturn(older);
        when(() => meta1.size).thenReturn(100);

        when(() => ref2.getMetadata()).thenAnswer((_) async => meta2);
        when(() => ref2.fullPath).thenReturn('path/backup2.lfbk');
        when(() => ref2.name).thenReturn('backup2.lfbk');
        when(() => meta2.timeCreated).thenReturn(newer);
        when(() => meta2.size).thenReturn(200);

        final backups = await provider.listBackups();

        expect(backups.length, equals(2));
        expect(backups[0].fileName, equals('backup2.lfbk'));
        expect(backups[0].createdAt, equals(newer));
        expect(backups[1].fileName, equals('backup1.lfbk'));
        expect(backups[1].createdAt, equals(older));
      });

      test('returns empty list when no backups exist', () async {
        final prefixRef = MockReference();
        final listResult = MockListResult();

        when(() => mockStorage.ref(any())).thenReturn(prefixRef);
        when(() => prefixRef.listAll()).thenAnswer((_) async => listResult);
        when(() => listResult.items).thenReturn([]);

        final backups = await provider.listBackups();

        expect(backups, isEmpty);
      });

      test('skips files that throw on getMetadata', () async {
        final prefixRef = MockReference();
        final goodRef = MockReference();
        final badRef = MockReference();
        final goodMeta = MockFullMetadata();
        final listResult = MockListResult();

        when(() => mockStorage.ref(any())).thenReturn(prefixRef);
        when(() => prefixRef.listAll()).thenAnswer((_) async => listResult);
        when(() => listResult.items).thenReturn([badRef, goodRef]);

        when(() => badRef.getMetadata()).thenThrow(Exception('access denied'));

        when(() => goodRef.getMetadata()).thenAnswer((_) async => goodMeta);
        when(() => goodRef.fullPath).thenReturn('path/good.lfbk');
        when(() => goodRef.name).thenReturn('good.lfbk');
        when(() => goodMeta.timeCreated).thenReturn(DateTime.utc(2026, 3, 6));
        when(() => goodMeta.size).thenReturn(50);

        final backups = await provider.listBackups();

        expect(backups.length, equals(1));
        expect(backups[0].fileName, equals('good.lfbk'));
      });

      test('uses fallback values when metadata fields are null', () async {
        final prefixRef = MockReference();
        final ref = MockReference();
        final meta = MockFullMetadata();
        final listResult = MockListResult();

        when(() => mockStorage.ref(any())).thenReturn(prefixRef);
        when(() => prefixRef.listAll()).thenAnswer((_) async => listResult);
        when(() => listResult.items).thenReturn([ref]);
        when(() => ref.getMetadata()).thenAnswer((_) async => meta);
        when(() => ref.fullPath).thenReturn('path/file.lfbk');
        when(() => ref.name).thenReturn('file.lfbk');
        when(() => meta.timeCreated).thenReturn(null);
        when(() => meta.size).thenReturn(null);

        final backups = await provider.listBackups();

        expect(backups.length, equals(1));
        expect(backups[0].sizeInBytes, equals(0));
        expect(backups[0].createdAt, isNotNull);
      });
    });

    group('delete', () {
      test('deletes file by metadata id', () async {
        final mockRef = MockReference();

        when(() => mockStorage.ref(any())).thenReturn(mockRef);
        when(() => mockRef.delete()).thenAnswer((_) async {});

        final metadata = BackupMetadata(
          id: 'backups/uid/folder/file.lfbk',
          fileName: 'file.lfbk',
          createdAt: DateTime.now(),
          sizeInBytes: 100,
        );

        await provider.delete(metadata);

        verify(() => mockStorage.ref('backups/uid/folder/file.lfbk')).called(1);
        verify(() => mockRef.delete()).called(1);
      });
    });

    group('_uid', () {
      test('throws StateError when no user is signed in', () async {
        when(() => mockAuth.currentUser).thenReturn(null);

        // _uid is accessed indirectly through upload/listBackups/etc.
        final mockRef = MockReference();
        when(() => mockStorage.ref(any())).thenReturn(mockRef);

        expect(
          () => provider.upload(fileName: 'test.lfbk', data: [1]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('requires an authenticated user'),
            ),
          ),
        );
      });

      test('uses custom subfolder in storage path', () async {
        final customProvider = FirebaseBackupProvider(
          storage: mockStorage,
          auth: mockAuth,
          subfolder: 'custom_dir',
        );

        final mockRef = MockReference();
        final mockMetadata = MockFullMetadata();

        when(() => mockStorage.ref(any())).thenReturn(mockRef);
        when(
          () => mockRef.putData(any(), any()),
        ).thenAnswer((_) => FakeUploadTask());
        when(() => mockRef.getMetadata()).thenAnswer((_) async => mockMetadata);
        when(() => mockRef.fullPath).thenReturn('path');
        when(() => mockMetadata.timeCreated).thenReturn(DateTime.utc(2026));
        when(() => mockMetadata.size).thenReturn(1);

        await customProvider.upload(fileName: 'f.lfbk', data: [1]);

        verify(
          () => mockStorage.ref('backups/test-uid-123/custom_dir/f.lfbk'),
        ).called(1);
      });
    });
  });
}
