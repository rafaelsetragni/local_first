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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'score': score,
    'note': note,
  };
}

class _DummyRepo extends LocalFirstRepository<_DummyModel> {
  _DummyRepo()
    : super(
        name: 'dummy',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: (json) => _DummyModel(
          id: json['id'] as String,
          name: json['name'] as String,
          score: json['score'] as int,
          note: json['note'] as String?,
        ),
        onConflict: (l, r) => l,
      );
}

class _FakeStorage extends LocalFirstStorage {
  _FakeStorage(this.items);

  List<Map<String, dynamic>> items;
  final Map<String, String> _meta = {};
  final Map<String, Map<String, dynamic>> _events = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> clearAllData() async {
    items = [];
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    return items;
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async {
    return items.firstWhere((e) => e['id'] == id, orElse: () => {}).isEmpty
        ? null
        : items.firstWhere((e) => e['id'] == id);
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {}

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {}

  @override
  Future<void> delete(String repositoryName, String id) async {}

  @override
  Future<void> deleteAll(String tableName) async {}

  @override
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName) async {
    return _events.values.toList();
  }

  @override
  Future<Map<String, dynamic>?> getEventById(String tableName, String id) async {
    return _events[id];
  }

  @override
  Future<void> insertEvent(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    _events[item[idField] as String] = item;
  }

  @override
  Future<void> updateEvent(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    _events[id] = item;
  }

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    _events.remove(id);
  }

  @override
  Future<void> deleteAllEvents(String tableName) async {
    _events.clear();
  }

  @override
  Future<void> setMeta(String key, String value) async {
    _meta[key] = value;
  }

  @override
  Future<String?> getMeta(String key) async => _meta[key];

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {}
}

void main() {
  group('LocalFirstQuery', () {
    late _FakeStorage storage;
    late LocalFirstQuery<_DummyModel> query;
    final repo = _DummyRepo();

    setUp(() {
      storage = _FakeStorage([
        {
          'id': '1',
          'name': 'alice',
          'score': 10,
          'note': null,
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
        },
        {
          'id': '2',
          'name': 'bob',
          'score': 20,
          'note': 'blue',
          '_sync_status': SyncStatus.pending.index,
          '_sync_operation': SyncOperation.update.index,
          '_sync_created_at': DateTime.utc(2024, 1, 2).millisecondsSinceEpoch,
        },
        {
          'id': '3',
          'name': 'charlie',
          'score': 30,
          'note': 'green',
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.delete.index,
          '_sync_created_at': DateTime.utc(2024, 1, 3).millisecondsSinceEpoch,
        },
        {
          'id': '4',
          'name': 'dave',
          'score': 15,
          'note': null,
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.utc(2024, 1, 4).millisecondsSinceEpoch,
        },
      ]);

      query = LocalFirstQuery<_DummyModel>(
        repositoryName: 'dummy',
        delegate: storage,
        fromJson: repo.fromJson,
        repository: repo,
      );
    });

    test('maps results and attaches sync metadata', () async {
      final results = await query.getAll();
      expect(results.length, 3); // delete filtered out

      final alice = results.firstWhere((m) => m.state.id == '1');
      expect(alice.state.name, 'alice');
      expect(alice.state.score, 10);
      expect(alice.syncStatus, SyncStatus.ok);
      expect(alice.syncOperation, SyncOperation.insert);
      expect(alice.repositoryName, 'dummy');
      expect(alice.syncCreatedAt, DateTime.utc(2024, 1, 1));
    });

    test('applies filtering, ordering, and pagination', () async {
      final results =
          await query //
              .where('name', isNotEqualTo: 'alice')
              .orderBy('name', descending: true)
              .limitTo(1)
              .getAll();

      expect(results.length, 1);
      expect(results.single.state.name, 'dave');
    });

    test('supports where equal and not equal', () async {
      final eq = await query.where('name', isEqualTo: 'alice').getAll();
      expect(eq.map((e) => e.state.name), ['alice']);

      final neq = await query.where('name', isNotEqualTo: 'alice').getAll();
      expect(neq.every((e) => e.state.name != 'alice'), isTrue);
    });

    test('supports greater/less comparisons', () async {
      final gt = await query.where('score', isGreaterThan: 10).getAll();
      expect(gt.map((e) => e.state.id), containsAll(['2', '4']));

      final gte = await query
          .where('score', isGreaterThanOrEqualTo: 20)
          .getAll();
      expect(gte.map((e) => e.state.id), contains('2'));

      final lt = await query.where('score', isLessThan: 20).getAll();
      expect(lt.map((e) => e.state.id), containsAll(['1', '4']));

      final lte = await query.where('score', isLessThanOrEqualTo: 10).getAll();
      expect(lte.map((e) => e.state.id), ['1']);
    });

    test('supports whereIn / whereNotIn', () async {
      final inList = await query
          .where('name', whereIn: ['alice', 'dave'])
          .getAll();
      expect(inList.map((e) => e.state.id), containsAll(['1', '4']));

      final notInList = await query
          .where('name', whereNotIn: ['alice', 'bob'])
          .getAll();
      expect(
        notInList.map((e) => e.state.name),
        everyElement(isNot(anyOf('alice', 'bob'))),
      );
    });

    test('supports isNull filter', () async {
      final nullNotes = await query.where('note', isNull: true).getAll();
      expect(nullNotes.map((e) => e.state.id), containsAll(['1', '4']));

      final notNullNotes = await query.where('note', isNull: false).getAll();
      expect(notNullNotes.map((e) => e.state.id), ['2']);
    });

    test('supports offset pagination', () async {
      final page = await query
          .orderBy('score')
      .startAfter(1)
      .limitTo(2)
      .getAll();
  expect(page.length, 2);
      expect(page.first.state.id, '4'); // scores: 10,15,20 (charlie is deleted)
    });

    test('watch emits initial mapped results', () async {
      final stream = query.watch();
      final first = await stream.first;

      expect(first.length, 3);
      expect(first.any((m) => m.state.id == '1'), isTrue);
      expect(first.any((m) => m.state.id == '2'), isTrue);
    });
  });
}
