import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _TestModel {
  _TestModel(this.id, {required this.username});

  final String id;
  final String username;

  factory _TestModel.fromJson(JsonMap json) =>
      _TestModel(json['id'] as String, username: json['username'] as String);

  JsonMap toJson() => {'id': id, 'username': username};
}

class _FakeStorage extends LocalFirstStorage {
  bool initialized = false;
  bool closed = false;
  bool cleared = false;
  final Map<String, String> meta = {};
  final List<JsonMap> events = [];
  List<LocalFirstEvent<dynamic>> lastEmittedEvents = const [];
  final StreamController<List<LocalFirstEvent<dynamic>>> _controller =
      StreamController.broadcast();

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }

  @override
  Future<void> clearAllData() async {
    cleared = true;
    events.clear();
  }

  @override
  Future<List<JsonMap>> getAll(String tableName) async => events;

  @override
  Future<List<JsonMap>> getAllEvents(String tableName) async => events;

  @override
  Future<JsonMap?> getById(String tableName, String id) async => events
      .cast<JsonMap?>()
      .firstWhere((e) => e != null && e['id'] == id, orElse: () => null);

  @override
  Future<bool> containsId(String tableName, String id) async =>
      events.any((e) => e['id'] == id);

  @override
  Future<JsonMap?> getEventById(String tableName, String id) async => events
      .cast<JsonMap?>()
      .firstWhere((e) => e != null && e['eventId'] == id, orElse: () => null);

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {
    events.add(item);
  }

  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {
    events.add(item);
  }

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {
    events.removeWhere((e) => e['id'] == id);
    events.add(item);
  }

  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {
    events.removeWhere((e) => e['eventId'] == id);
    events.add(item);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    events.removeWhere((e) => e['id'] == id);
  }

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    events.removeWhere((e) => e['eventId'] == id);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    events.clear();
  }

  @override
  Future<void> deleteAllEvents(String tableName) async {
    events.clear();
  }

  @override
  Future<void> setMeta(String key, String value) async {
    meta[key] = value;
  }

  @override
  Future<String?> getMeta(String key) async => meta[key];

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async =>
      lastEmittedEvents.cast<LocalFirstEvent<T>>();

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) =>
      _controller.stream.map((e) => e.cast<LocalFirstEvent<T>>());

  void emitEvents(List<LocalFirstEvent<dynamic>> items) {
    lastEmittedEvents = items;
    _controller.add(items);
  }
}

void main() {
  group('LocalFirstStorage contract', () {
    late _FakeStorage storage;

    setUp(() {
      storage = _FakeStorage();
    });

    test('initialize/close toggle flags', () async {
      await storage.initialize();
      expect(storage.initialized, isTrue);

      await storage.close();
      expect(storage.closed, isTrue);
    });

    test('set/get meta', () async {
      await storage.setMeta('k', 'v');
      expect(await storage.getMeta('k'), 'v');
    });

    test('insert/update/delete data', () async {
      await storage.insert('t', {'id': '1'}, 'id');
      expect(await storage.getById('t', '1'), isNotNull);

      await storage.update('t', '1', {'id': '1', 'field': 'x'});
      expect((await storage.getById('t', '1'))?['field'], 'x');

      await storage.delete('t', '1');
      expect(await storage.getById('t', '1'), isNull);
    });

    test('insert/update/delete events', () async {
      await storage.insertEvent('t', {'eventId': 'e1'}, 'eventId');
      expect(await storage.getEventById('t', 'e1'), isNotNull);

      await storage.updateEvent('t', 'e1', {'eventId': 'e1', 'v': 1});
      expect((await storage.getEventById('t', 'e1'))?['v'], 1);

      await storage.deleteEvent('t', 'e1');
      expect(await storage.getEventById('t', 'e1'), isNull);
    });

    test('clear/deleteAll wipe state', () async {
      await storage.insert('t', {'id': '1'}, 'id');
      await storage.deleteAll('t');
      expect(await storage.getAll('t'), isEmpty);

      await storage.insertEvent('t', {'eventId': 'e'}, 'eventId');
      await storage.deleteAllEvents('t');
      expect(await storage.getAllEvents('t'), isEmpty);
    });

    test('containsId checks state presence', () async {
      await storage.insert('t', {'id': '1'}, 'id');
      expect(await storage.containsId('t', '1'), isTrue);
      expect(await storage.containsId('t', 'missing'), isFalse);
    });

    test('query/watchQuery emit provided events', () async {
      final repo = LocalFirstRepository<_TestModel>.create(
        name: 'users',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
      );
      final query = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        repository: repo,
      );
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: _TestModel('1', username: 'alice'),
        needSync: true,
      );

      // emit through watchQuery
      final emissions = <List<LocalFirstEvent<_TestModel>>>[];
      final sub = storage.watchQuery(query).listen(emissions.add);
      storage.emitEvents([event]);

      final queried = await storage.query(query);

      expect(emissions.single.single.eventId, event.eventId);
      expect(queried.single.eventId, event.eventId);

      await sub.cancel();
    });
  });
}
