import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

/// In-memory [BackupStorageProvider] for testing.
class MockBackupStorageProvider implements BackupStorageProvider {
  final Map<String, List<int>> _files = {};
  final Map<String, BackupMetadata> _metadata = {};
  int _nextId = 1;

  @override
  Future<BackupMetadata> upload({
    required String fileName,
    required List<int> data,
  }) async {
    final id = 'mock-${_nextId++}';
    _files[id] = List<int>.from(data);
    final metadata = BackupMetadata(
      id: id,
      fileName: fileName,
      createdAt: DateTime.now().toUtc(),
      sizeInBytes: data.length,
    );
    _metadata[id] = metadata;
    return metadata;
  }

  @override
  Future<List<int>> download(BackupMetadata metadata) async {
    final data = _files[metadata.id];
    if (data == null) throw StateError('Backup not found: ${metadata.id}');
    return List<int>.from(data);
  }

  @override
  Future<List<BackupMetadata>> listBackups() async {
    final list = _metadata.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> delete(BackupMetadata metadata) async {
    _files.remove(metadata.id);
    _metadata.remove(metadata.id);
  }
}

class _TestRepository extends LocalFirstRepository<Map<String, dynamic>> {
  _TestRepository(String name)
    : super(
        name: name,
        getId: (item) => item['id'] as String,
        toJson: (item) => Map<String, dynamic>.from(item),
        fromJson: (json) => Map<String, dynamic>.from(json),
      );
}

void main() {
  late InMemoryLocalFirstStorage storage;
  late LocalFirstClient client;
  late BackupService backupService;
  late MockBackupStorageProvider provider;
  const password = 'test-backup-password';

  setUp(() async {
    storage = InMemoryLocalFirstStorage();
    client = LocalFirstClient(
      localStorage: storage,
      repositories: [
        _TestRepository('todos'),
        _TestRepository('notes'),
      ],
    );
    await client.initialize();
    backupService = BackupService(client: client);
    provider = MockBackupStorageProvider();
  });

  tearDown(() async {
    await client.dispose();
  });

  group('BackupService', () {
    group('createBackup', () {
      test('creates backup with empty repositories', () async {
        final metadata = await backupService.createBackup(
          provider: provider,
          password: password,
        );

        expect(metadata.fileName, startsWith('backup_'));
        expect(metadata.fileName, endsWith('.lfbk'));
        expect(metadata.sizeInBytes, greaterThan(0));
      });

      test('creates backup with data', () async {
        // Insert some data
        final todosRepo = client.getRepositoryByName('todos');
        await todosRepo.upsert({'id': 't1', 'title': 'Buy milk', 'done': false});
        await todosRepo.upsert({'id': 't2', 'title': 'Walk dog', 'done': true});

        final notesRepo = client.getRepositoryByName('notes');
        await notesRepo.upsert({
          'id': 'n1',
          'title': 'Note 1',
          'body': 'Content',
        });

        final metadata = await backupService.createBackup(
          provider: provider,
          password: password,
        );

        expect(metadata.sizeInBytes, greaterThan(0));

        // Verify the backup is listed
        final backups = await backupService.listBackups(provider);
        expect(backups.length, equals(1));
        expect(backups.first.id, equals(metadata.id));
      });

      test('creates backup with config values', () async {
        await client.setConfigValue('lastSync', '2026-03-06T12:00:00Z');
        await client.setConfigValue('userName', 'Alice');

        final metadata = await backupService.createBackup(
          provider: provider,
          password: password,
        );

        expect(metadata.sizeInBytes, greaterThan(0));
      });
    });

    group('restoreBackup', () {
      test('restores data to empty client', () async {
        // Create data and backup
        final todosRepo = client.getRepositoryByName('todos');
        await todosRepo.upsert({'id': 't1', 'title': 'Buy milk', 'done': false});
        await todosRepo.upsert({'id': 't2', 'title': 'Walk dog', 'done': true});

        await client.setConfigValue('lastSync', '2026-03-06T12:00:00Z');

        final metadata = await backupService.createBackup(
          provider: provider,
          password: password,
        );

        // Create a fresh client and restore
        await client.dispose();
        final newStorage = InMemoryLocalFirstStorage();
        final newClient = LocalFirstClient(
          localStorage: newStorage,
          repositories: [
            _TestRepository('todos'),
            _TestRepository('notes'),
          ],
        );
        await newClient.initialize();
        final newBackupService = BackupService(client: newClient);

        await newBackupService.restoreBackup(
          provider: provider,
          metadata: metadata,
          password: password,
        );

        // Verify data was restored
        final restoredTodos =
            await newStorage.getAll('todos');
        expect(restoredTodos.length, equals(2));

        // Verify config was restored
        final lastSync = await newClient.getConfigValue('lastSync');
        expect(lastSync, equals('2026-03-06T12:00:00Z'));

        await newClient.dispose();
      });

      test('incremental restore skips existing events', () async {
        // Create initial data
        final todosRepo = client.getRepositoryByName('todos');
        await todosRepo.upsert({'id': 't1', 'title': 'Buy milk', 'done': false});

        // Create backup
        final metadata = await backupService.createBackup(
          provider: provider,
          password: password,
        );

        // Add more data after backup
        await todosRepo.upsert({'id': 't2', 'title': 'Walk dog', 'done': true});

        // Restore on same client (should not duplicate t1)
        await backupService.restoreBackup(
          provider: provider,
          metadata: metadata,
          password: password,
        );

        // t1 should exist once, t2 should also still exist
        final todos = await storage.getAll('todos');
        final t1Count =
            todos.where((t) => t['id'] == 't1').length;
        expect(t1Count, equals(1));
        expect(
          todos.where((t) => t['id'] == 't2').length,
          equals(1),
        );
      });

      test('wrong password throws FormatException', () async {
        await backupService.createBackup(
          provider: provider,
          password: password,
        );

        final backups = await backupService.listBackups(provider);

        expect(
          () => backupService.restoreBackup(
            provider: provider,
            metadata: backups.first,
            password: 'wrong-password',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('skips unknown repositories gracefully', () async {
        // Create data
        final todosRepo = client.getRepositoryByName('todos');
        await todosRepo.upsert({'id': 't1', 'title': 'Buy milk', 'done': false});

        final metadata = await backupService.createBackup(
          provider: provider,
          password: password,
        );

        // Restore to a client with fewer repositories
        await client.dispose();
        final newStorage = InMemoryLocalFirstStorage();
        final newClient = LocalFirstClient(
          localStorage: newStorage,
          repositories: [
            _TestRepository('todos'),
            // 'notes' is NOT registered
          ],
        );
        await newClient.initialize();
        final newBackupService = BackupService(client: newClient);

        // Should not throw even though 'notes' is in the backup
        await newBackupService.restoreBackup(
          provider: provider,
          metadata: metadata,
          password: password,
        );

        await newClient.dispose();
      });
    });

    group('listBackups', () {
      test('returns backups newest first', () async {
        await backupService.createBackup(
          provider: provider,
          password: password,
        );
        await backupService.createBackup(
          provider: provider,
          password: password,
        );

        final backups = await backupService.listBackups(provider);
        expect(backups.length, equals(2));
        expect(
          backups.first.createdAt.isAfter(backups.last.createdAt) ||
              backups.first.createdAt == backups.last.createdAt,
          isTrue,
        );
      });
    });

    group('deleteBackup', () {
      test('removes backup from provider', () async {
        final metadata = await backupService.createBackup(
          provider: provider,
          password: password,
        );

        var backups = await backupService.listBackups(provider);
        expect(backups.length, equals(1));

        await backupService.deleteBackup(
          provider: provider,
          metadata: metadata,
        );

        backups = await backupService.listBackups(provider);
        expect(backups.length, equals(0));
      });
    });
  });
}
