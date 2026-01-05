import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _DummyModel {
  _DummyModel({
    required this.id,
    required this.name,
    required this.score,
    this.note,
  });

  final String id;
  final String name;
  final int score;
  final String? note;
}

class _FakeStorage extends LocalFirstStorage {
  _FakeStorage(this.items);

  List<JsonMap<dynamic>> items;
  final Map<String, JsonMap<dynamic>> _events = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> clearAllData() async {
    items = [];
  }

  @override
  Future<List<JsonMap<dynamic>>> getAll(String tableName) async {
    return items;
  }

  @override
  Future<JsonMap<dynamic>?> getById(String tableName, String id) async {
    return items.firstWhere((e) => e['id'] == id, orElse: () => {}).isEmpty
        ? null
        : items.firstWhere((e) => e['id'] == id);
  }

  @override
  Future<void> insert(
    String tableName,
    JsonMap<dynamic> item,
    String idField,
  ) async {}

  @override
  Future<void> update(
    String tableName,
    String id,
    JsonMap<dynamic> item,
  ) async {}

  @override
  Future<void> delete(String repositoryName, String id) async {}

  @override
  Future<void> deleteAll(String tableName) async {}

  @override
  Future<void> pullRemoteEvent(JsonMap<dynamic> event) async {
    _events[event['event_id'] as String? ?? UniqueKey().toString()] = Map.of(
      event,
    );
  }

  @override
  Future<JsonMap<dynamic>?> getEventById(String eventId) async =>
      _events[eventId] == null ? null : Map.of(_events[eventId]!);

  @override
  Future<List<JsonMap<dynamic>>> getEvents({String? repositoryName}) async {
    return _events.values
        .where(
          (e) => repositoryName == null || e['repository'] == repositoryName,
        )
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    _events.remove(eventId);
  }

  @override
  Future<void> clearEvents() async {
    _events.clear();
  }

  @override
  Future<void> pruneEvents(DateTime before) async {
    _events.removeWhere((_, e) {
      final ts = e['created_at'];
      return ts is int && ts < before.toUtc().millisecondsSinceEpoch;
    });
  }

  @override
  Future<List<JsonMap<dynamic>>> query(LocalFirstQuery query) async {
    return items
        .where((e) => e['repository']?.toString() == query.repositoryName)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {}
}

void main() {
  group('LocalFirstQuery', () {
    late _FakeStorage storage;
    late LocalFirstQuery<_DummyModel> query;
    final repo = LocalFirstRepository<_DummyModel>.create(
      name: 'dummy',
      getId: (m) => m.id,
      toJson: (_) => {},
      fromJson: (json) => _DummyModel(
        id: json['id'] as String,
        name: json['name'] as String,
        score: json['score'] as int,
        note: json['note'] as String?,
      ),
      onConflictEvent: (l, r) => r,
    );

    setUp(() {
      storage = _FakeStorage([
        {
          'repository': 'dummy',
          'record_id': '1',
          'event_id': 'e1',
          'payload': {'id': '1', 'name': 'alice', 'score': 10, 'note': null},
          'status': SyncStatus.ok.index,
          'operation': SyncOperation.insert.index,
          'created_at': DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
          'server_sequence': 1,
        },
        {
          'repository': 'dummy',
          'record_id': '2',
          'event_id': 'e2',
          'payload': {'id': '2', 'name': 'bob', 'score': 20, 'note': 'blue'},
          'status': SyncStatus.pending.index,
          'operation': SyncOperation.update.index,
          'created_at': DateTime.utc(2024, 1, 2).millisecondsSinceEpoch,
          'server_sequence': 2,
        },
        {
          'repository': 'dummy',
          'record_id': '3',
          'event_id': 'e3',
          'payload': {
            'id': '3',
            'name': 'charlie',
            'score': 30,
            'note': 'green',
          },
          'status': SyncStatus.ok.index,
          'operation': SyncOperation.delete.index,
          'created_at': DateTime.utc(2024, 1, 3).millisecondsSinceEpoch,
          'server_sequence': 3,
        },
        {
          'repository': 'dummy',
          'record_id': '4',
          'event_id': 'e4',
          'payload': {'id': '4', 'name': 'dave', 'score': 15, 'note': null},
          'status': SyncStatus.ok.index,
          'operation': SyncOperation.insert.index,
          'created_at': DateTime.utc(2024, 1, 4).millisecondsSinceEpoch,
          'server_sequence': 4,
        },
      ]);

      query = LocalFirstQuery<_DummyModel>(
        repositoryName: 'dummy',
        delegate: storage,
        fromEvent: (json) => LocalFirstEvent.fromJson<_DummyModel>(
          json,
          fromJson: (payload) => repo.fromJson(payload),
        ),
      );
    });

    test('maps results and attaches sync metadata', () async {
      final results = await query.getAll();
      expect(results.length, 3); // delete filtered out

      final alice = results.firstWhere((m) => m.id == '1');
      expect(alice.name, 'alice');
      expect(alice.score, 10);
      expect(alice.name, 'alice');
      expect(alice.score, 10);
    });

    test('applies filtering, ordering, and pagination', () async {
      final results =
          await query //
              .where('name', isNotEqualTo: 'alice')
              .orderBy('name', descending: true)
              .limitTo(1)
              .getAll();

      expect(results.length, 1);
      expect(results.single.name, 'dave');
    });

    test('supports where equal and not equal', () async {
      final eq = await query.where('name', isEqualTo: 'alice').getAll();
      expect(eq.map((e) => e.name), ['alice']);

      final neq = await query.where('name', isNotEqualTo: 'alice').getAll();
      expect(neq.every((e) => e.name != 'alice'), isTrue);
    });

    test('supports greater/less comparisons', () async {
      final gt = await query.where('score', isGreaterThan: 10).getAll();
      expect(gt.map((e) => e.id), containsAll(['2', '4']));

      final gte = await query
          .where('score', isGreaterThanOrEqualTo: 20)
          .getAll();
      expect(gte.map((e) => e.id), contains('2'));

      final lt = await query.where('score', isLessThan: 20).getAll();
      expect(lt.map((e) => e.id), containsAll(['1', '4']));

      final lte = await query.where('score', isLessThanOrEqualTo: 10).getAll();
      expect(lte.map((e) => e.id), ['1']);
    });

    test('supports whereIn / whereNotIn', () async {
      final inList = await query
          .where('name', whereIn: ['alice', 'dave'])
          .getAll();
      expect(inList.map((e) => e.id), containsAll(['1', '4']));

      final notInList = await query
          .where('name', whereNotIn: ['alice', 'bob'])
          .getAll();
      expect(
        notInList.map((e) => e.name),
        everyElement(isNot(anyOf('alice', 'bob'))),
      );
    });

    test('supports isNull filter', () async {
      final nullNotes = await query.where('note', isNull: true).getAll();
      expect(nullNotes.map((e) => e.id), containsAll(['1', '4']));

      final notNullNotes = await query.where('note', isNull: false).getAll();
      expect(notNullNotes.map((e) => e.id), ['2']);
    });

    test('supports offset pagination', () async {
      final page = await query
          .orderBy('score')
          .startAfter(1)
          .limitTo(2)
          .getAll();
      expect(page.length, 2);
      expect(page.first.id, '4'); // scores: 10,15,20 (charlie is deleted)
    });

    test('watch emits initial mapped results', () async {
      final stream = query.watch();
      final first = await stream.first;

      expect(first.length, 3);
      expect(first.any((m) => m.id == '1'), isTrue);
      expect(first.any((m) => m.id == '2'), isTrue);
    });
  });
}
