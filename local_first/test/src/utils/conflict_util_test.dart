import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('ConflictUtil.lastWriteWins', () {
    late LocalFirstRepository<JsonMap> repository;

    setUp(() {
      repository = LocalFirstRepository<JsonMap>.create(
        name: 'repo',
        getId: (item) => item['id'] as String,
        toJson: (item) => item,
        fromJson: (json) => json,
      );
    });

    LocalFirstEvent<JsonMap> eventAt(DateTime createdAt) {
      return LocalFirstEvent<JsonMap>.fromRemoteJson(
        repository: repository,
        json: {
          LocalFirstEvent.kRepository: repository.name,
          LocalFirstEvent.kEventId: IdUtil.uuidV7(),
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: createdAt.millisecondsSinceEpoch,
          LocalFirstEvent.kDataId: '1',
          LocalFirstEvent.kData: {'id': '1'},
        },
      );
    }

    test('should return local when it is newer', () {
      final remote = eventAt(
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      final local = eventAt(
        DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      );

      final result = ConflictUtil.lastWriteWins(local, remote);

      expect(result, same(local));
    });

    test('should return remote when it is newer', () {
      final local = eventAt(
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      final remote = eventAt(
        DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      );

      final result = ConflictUtil.lastWriteWins(local, remote);

      expect(result, same(remote));
    });

    test('should return remote when timestamps are equal', () {
      final timestamp = DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true);
      final local = eventAt(timestamp);
      final remote = eventAt(timestamp);

      final result = ConflictUtil.lastWriteWins(local, remote);

      expect(result, same(remote));
    });
  });
}
