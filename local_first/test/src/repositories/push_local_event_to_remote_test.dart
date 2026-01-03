import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _TestModel {
  _TestModel(this.id);
  final String id;
  JsonMap toJson() => {'id': id};
}

class _RecordingStrategy extends DataSyncStrategy<_TestModel> {
  final List<LocalFirstEvent> seen = [];
  final List<SyncStatus Function()> responses;
  int index = 0;

  _RecordingStrategy(this.responses);

  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent event) async {
    seen.add(event);
    final resp = responses[index.clamp(0, responses.length - 1)]();
    index++;
    return resp;
  }
}

void main() {
  group('_pushLocalEventToRemote', () {
    late LocalFirstRepository<_TestModel> repo;
    late LocalFirstRepositoryTestAdapter<_TestModel> adapter;

    setUp(() {
      repo = LocalFirstRepository.create<_TestModel>(
        name: 'tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: (json) => _TestModel(json['id'] as String),
        onConflict: (l, r) => r,
      );
      // minimal client and storage for adapter calls that don't hit storage
      repo._client = LocalFirstClient(
        repositories: [repo],
        localStorage: InMemoryLocalFirstStorage(),
        metaStorage: InMemoryKeyValueStorage(),
        syncStrategies: [],
      );
      repo._syncStrategies = [];
      adapter = LocalFirstRepositoryTestAdapter(repo);
    });

    test('returns immediately when no strategy supports event', () async {
      final event = LocalFirstEvent(
        data: _TestModel('1'),
        repositoryName: 'tests',
        syncOperation: SyncOperation.insert,
        syncStatus: SyncStatus.pending,
      );
      await adapter.pushLocalEventToRemote(event);

      // no strategies, so storage should remain empty
      final stored = await repo.delegate.getById('tests', '1');
      expect(stored, isNull);
    });

    test('chooses highest status among strategies', () async {
      final s1 = _RecordingStrategy([
        () => SyncStatus.pending,
        () => SyncStatus.ok,
      ]);
      final s2 = _RecordingStrategy([
        () => SyncStatus.failed,
        () => SyncStatus.pending,
      ]);
      repo._syncStrategies = [s1, s2];
      final event = LocalFirstEvent(
        data: _TestModel('1'),
        repositoryName: 'tests',
        syncOperation: SyncOperation.insert,
        syncStatus: SyncStatus.pending,
      );

      // attach minimal storage to observe status update
      final storage = InMemoryLocalFirstStorage();
      repo._client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        metaStorage: InMemoryKeyValueStorage(),
        syncStrategies: [],
      );

      await adapter.pushLocalEventToRemote(event);

      // both strategies were called
      expect(s1.seen.length, 1);
      expect(s2.seen.length, 1);

      // highest status among [pending (initial), failed, pending] is failed
      final stored = await storage.getById('tests', '1');
      expect(stored?['_sync_status'], SyncStatus.failed.index);
    });

    test('marks failed on exception', () async {
      final failing = _RecordingStrategy([() => throw Exception('boom')]);
      repo._syncStrategies = [failing];
      final storage = InMemoryLocalFirstStorage();
      repo._client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        metaStorage: InMemoryKeyValueStorage(),
        syncStrategies: [],
      );
      final event = LocalFirstEvent(
        data: _TestModel('1'),
        repositoryName: 'tests',
        syncOperation: SyncOperation.insert,
        syncStatus: SyncStatus.pending,
      );

      await adapter.pushLocalEventToRemote(event);
      final stored = await storage.getById('tests', '1');
      expect(stored?['_sync_status'], SyncStatus.failed.index);
    });
  });
}
