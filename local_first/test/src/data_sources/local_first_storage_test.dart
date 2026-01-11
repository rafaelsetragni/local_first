import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _FakeStorage extends LocalFirstStorage {
  bool ensureCalled = false;
  String? lastTable;
  Map<String, LocalFieldType>? lastSchema;
  String? lastIdField;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> clearAllData() async {}

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async => const [];

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async =>
      null;

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
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName) async =>
      const [];

  @override
  Future<Map<String, dynamic>?> getEventById(
    String tableName,
    String id,
  ) async => null;

  @override
  Future<void> insertEvent(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {}

  @override
  Future<void> updateEvent(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {}

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {}

  @override
  Future<void> deleteAllEvents(String tableName) async {}

  @override
  Future<void> setKey(String key, String value) async {}

  @override
  Future<String?> getKey(String key) async => null;

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
}
