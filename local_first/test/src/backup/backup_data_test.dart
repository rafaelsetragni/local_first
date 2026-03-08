import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('BackupRepositoryData', () {
    test('toJson/fromJson roundtrip', () {
      final data = BackupRepositoryData(
        repositoryName: 'todos',
        stateRows: [
          {'id': '1', 'title': 'Buy milk', 'done': false},
          {'id': '2', 'title': 'Walk dog', 'done': true},
        ],
        eventRows: [
          {
            '_event_id': 'evt-1',
            '_data_id': '1',
            '_operation': 0,
            '_sync_status': 1,
            '_created_at': 1709740800000,
          },
          {
            '_event_id': 'evt-2',
            '_data_id': '2',
            '_operation': 0,
            '_sync_status': 1,
            '_created_at': 1709740900000,
          },
        ],
      );

      final json = data.toJson();
      final restored = BackupRepositoryData.fromJson(json);

      expect(restored.repositoryName, equals('todos'));
      expect(restored.stateRows.length, equals(2));
      expect(restored.eventRows.length, equals(2));
      expect(restored.stateRows[0]['title'], equals('Buy milk'));
      expect(restored.eventRows[0]['_event_id'], equals('evt-1'));
    });
  });

  group('BackupData', () {
    test('toJson/fromJson roundtrip', () {
      final now = DateTime.utc(2026, 3, 6, 12, 0, 0);
      final data = BackupData(
        version: 1,
        createdAt: now,
        namespace: 'user-123',
        repositories: [
          BackupRepositoryData(
            repositoryName: 'todos',
            stateRows: [
              {'id': '1', 'title': 'Test'},
            ],
            eventRows: [
              {'_event_id': 'e1', '_data_id': '1', '_operation': 0},
            ],
          ),
          BackupRepositoryData(
            repositoryName: 'notes',
            stateRows: [],
            eventRows: [],
          ),
        ],
        config: {
          'lastSync': '2026-03-06T11:00:00Z',
          'syncEnabled': true,
          'retryCount': 3,
        },
      );

      final json = data.toJson();
      final restored = BackupData.fromJson(json);

      expect(restored.version, equals(1));
      expect(restored.createdAt, equals(now));
      expect(restored.namespace, equals('user-123'));
      expect(restored.repositories.length, equals(2));
      expect(restored.repositories[0].repositoryName, equals('todos'));
      expect(restored.repositories[1].repositoryName, equals('notes'));
      expect(restored.config['lastSync'], equals('2026-03-06T11:00:00Z'));
      expect(restored.config['syncEnabled'], equals(true));
      expect(restored.config['retryCount'], equals(3));
    });

    test('toJson/fromJson without namespace', () {
      final data = BackupData(
        version: 1,
        createdAt: DateTime.utc(2026, 1, 1),
        repositories: [],
        config: {},
      );

      final json = data.toJson();
      expect(json.containsKey('namespace'), isFalse);

      final restored = BackupData.fromJson(json);
      expect(restored.namespace, isNull);
    });

    test('currentVersion is 1', () {
      expect(BackupData.currentVersion, equals(1));
    });
  });
}
