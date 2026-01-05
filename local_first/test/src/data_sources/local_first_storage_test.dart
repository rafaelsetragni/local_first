import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _FakeStorage extends LocalFirstStorage {
  bool ensureCalled = false;
  String? lastTable;
  JsonMap<LocalFieldType>? lastSchema;
  String? lastIdField;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> clearAllData() async {}

  @override
  Future<List<JsonMap<dynamic>>> getAll(String tableName) async => const [];

  @override
  Future<JsonMap<dynamic>?> getById(String tableName, String id) async => null;

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
  Future<void> setMeta(String key, String value) async {}

  @override
  Future<String?> getMeta(String key) async => null;

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
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
