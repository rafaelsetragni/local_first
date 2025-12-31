import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _FakeStorage extends LocalFirstStorage {
  bool ensureCalled = false;
  String? lastTable;
  Map<String, LocalFieldType>? lastSchema;
  String? lastIdField;
  final Map<String, String> meta = {};

  @override
  Future<void> open({String namespace = 'default'}) async {}

  @override
  bool get isOpened => true;

  @override
  bool get isClosed => false;

  @override
  String get currentNamespace => 'default';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> clearAllData() async {}

  @override
  Future<List<JsonMap>> getAll(String tableName) async => const [];

  @override
  Future<JsonMap?> getById(String tableName, String id) async => null;

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {}

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {}

  @override
  Future<void> delete(String repositoryName, String id) async {}

  @override
  Future<void> deleteAll(String tableName) async {}

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
  }) async {
    ensureCalled = true;
    lastTable = tableName;
    lastSchema = schema;
    lastIdField = idFieldName;
    await super.ensureSchema(tableName, schema, idFieldName: idFieldName);
  }
}

void main() {
  test('LocalFirstStorage.ensureSchema can be invoked via contract', () async {
    final storage = _FakeStorage();
    const schema = {'name': LocalFieldType.text};

    await storage.ensureSchema('users', schema, idFieldName: 'id');

    expect(storage.ensureCalled, isTrue);
    expect(storage.lastTable, 'users');
    expect(storage.lastSchema, schema);
    expect(storage.lastIdField, 'id');
  });

  test(
    'registerEvent stores event id and isEventRegistered reflects it',
    () async {
      final storage = _FakeStorage();
      final eventId = 'event-1';
      final createdAt = DateTime.utc(2024, 1, 1);

      expect(await storage.isEventRegistered(eventId), isFalse);

      await storage.registerEvent(eventId, createdAt);

      expect(await storage.isEventRegistered(eventId), isTrue);
      expect(
        storage.meta['__event_id__$eventId'],
        createdAt.millisecondsSinceEpoch.toString(),
      );
    },
  );

  test(
    'pruneRegisteredEvents default implementation does not remove events',
    () async {
      final storage = _FakeStorage();
      final eventId = 'event-2';
      final createdAt = DateTime.utc(2023, 1, 1);

      await storage.registerEvent(eventId, createdAt);
      await storage.pruneRegisteredEvents(DateTime.utc(2025, 1, 1));

      expect(await storage.isEventRegistered(eventId), isTrue);
    },
  );
}
