import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _DummyModel {
  _DummyModel(this.id, {this.value});
  final String id;
  final String? value;

  JsonMap toJson() => {'id': id, if (value != null) 'value': value};
}

LocalFirstRepository<_DummyModel> _dummyRepo() {
  return LocalFirstRepository.create(
    name: 'dummy',
    getId: (m) => m.id,
    toJson: (m) => m.toJson(),
    fromJson: (j) =>
        _DummyModel(j['id'] as String, value: j['value'] as String?),
    onConflictEvent: (l, r) => r,
  );
}

class _StorageStub implements LocalFirstStorage {
  LocalFirstQuery? lastQuery;
  List<LocalFirstEvent> result = const [];
  final StreamController<List<LocalFirstEvent>> controller =
      StreamController<List<LocalFirstEvent>>.broadcast();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {
    await controller.close();
  }

  @override
  Future<void> clearAllData() async {}

  @override
  Future<List<JsonMap>> getAll(String tableName) async => const [];

  @override
  Future<List<JsonMap>> getAllEvents(String tableName) async => const [];

  @override
  Future<JsonMap?> getById(String tableName, String id) async => null;

  @override
  Future<JsonMap?> getEventById(String tableName, String id) async => null;

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {}

  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {}

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {}

  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {}

  @override
  Future<void> delete(String repositoryName, String id) async {}

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {}

  @override
  Future<void> deleteAll(String tableName) async {}

  @override
  Future<void> deleteAllEvents(String tableName) async {}

  @override
  Future<void> setString(String key, String value) async {}

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<bool> containsId(String tableName, String id) async => false;

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async {
    lastQuery = query;
    return result.cast<LocalFirstEvent<T>>();
  }

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) {
    lastQuery = query;
    return controller.stream.map((e) => e.cast<LocalFirstEvent<T>>());
  }
}

void main() {
  group('LocalFirstQuery', () {
    late _StorageStub storage;
    late LocalFirstRepository<_DummyModel> repo;

    setUp(() {
      storage = _StorageStub();
      repo = _dummyRepo();
    });

    group('copyWith', () {
      test('should keep original values when no overrides provided', () {
        final base = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
          filters: [const QueryFilter(field: 'a')],
          sorts: const [QuerySort(field: 'b')],
          limit: 1,
          offset: 2,
          includeDeleted: true,
        );

        final copy = base.copyWith();

        expect(copy.repositoryName, base.repositoryName);
        expect(copy.filters, base.filters);
        expect(copy.sorts, base.sorts);
        expect(copy.limit, 1);
        expect(copy.offset, 2);
        expect(copy.includeDeleted, isTrue);
      });

      test('should apply overrides to filters and pagination', () {
        final base = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final copy = base.copyWith(
          filters: [const QueryFilter(field: 'x')],
          sorts: const [QuerySort(field: 'y', descending: true)],
          limit: 10,
          offset: 5,
          includeDeleted: true,
        );

        expect(copy.filters.single.field, 'x');
        expect(copy.sorts.single.field, 'y');
        expect(copy.limit, 10);
        expect(copy.offset, 5);
        expect(copy.includeDeleted, isTrue);
      });
    });

    group('where', () {
      test('should add filter to existing list', () {
        final query = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final filtered = query.where('name', isEqualTo: 'a');

        expect(filtered.filters.length, 1);
        final filter = filtered.filters.first;
        expect(filter.field, 'name');
        expect(filter.isEqualTo, 'a');
      });
    });

    group('orderBy', () {
      test('should append sort configuration', () {
        final query = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final sorted = query.orderBy('createdAt', descending: true);

        expect(sorted.sorts.length, 1);
        expect(sorted.sorts.first.field, 'createdAt');
        expect(sorted.sorts.first.descending, isTrue);
      });
    });

    group('limitTo', () {
      test('should set pagination limit on query', () {
        final query = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final limited = query.limitTo(5);

        expect(limited.limit, 5);
      });
    });

    group('startAfter', () {
      test('should set pagination offset on query', () {
        final query = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final offsetQuery = query.startAfter(3);

        expect(offsetQuery.offset, 3);
      });
    });

    group('withDeleted', () {
      test('should toggle includeDeleted flag correctly', () {
        final query = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final withDel = query.withDeleted(include: true);
        final withoutDel = query.withDeleted(include: false);

        expect(withDel.includeDeleted, isTrue);
        expect(withoutDel.includeDeleted, isFalse);
      });
    });

    group('getAll', () {
      test('should delegate execution to storage', () async {
        final event = LocalFirstEvent.createNewInsertEvent(
          repository: repo,
          needSync: true,
          data: _DummyModel('1'),
        );
        storage.result = [event];

        final query = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final result = await query.getAll();

        expect(storage.lastQuery, same(query));
        expect(result, contains(event));
      });
    });

    group('watch', () {
      test('should delegate watch to storage stream', () async {
        final query = LocalFirstQuery<_DummyModel>(
          repositoryName: 'dummy',
          delegate: storage,
          repository: repo,
        );

        final stream = query.watch();
        final events = <List<LocalFirstEvent<_DummyModel>>>[];
        final sub = stream.listen(events.add);

        final event = LocalFirstEvent.createNewInsertEvent(
          repository: repo,
          needSync: true,
          data: _DummyModel('2'),
        );
        storage.controller.add([event]);
        await Future<void>.delayed(Duration.zero);

        expect(storage.lastQuery, same(query));
        expect(events.single, contains(event));
        await sub.cancel();
      });
    });

    group('QueryFilter.matches', () {
      test(
        'should match when value equals isEqualTo and not in isNotEqualTo',
        () {
          const filter = QueryFilter(field: 'a', isEqualTo: 1);
          expect(filter.matches({'a': 1}), isTrue);
          expect(filter.matches({'a': 2}), isFalse);
        },
      );

      test('should respect null checks when isNull set', () {
        const filterNull = QueryFilter(field: 'a', isNull: true);
        const filterNotNull = QueryFilter(field: 'a', isNull: false);

        expect(filterNull.matches({'a': null}), isTrue);
        expect(filterNull.matches({'a': 1}), isFalse);
        expect(filterNotNull.matches({'a': 1}), isTrue);
        expect(filterNotNull.matches({'a': null}), isFalse);
      });

      test('should evaluate comparison operators for comparable values', () {
        const filter = QueryFilter(
          field: 'a',
          isLessThan: 10,
          isGreaterThan: 1,
        );
        expect(filter.matches({'a': 5}), isTrue);
        expect(filter.matches({'a': 0}), isFalse);
        expect(filter.matches({'a': 11}), isFalse);
      });

      test('should evaluate whereIn and whereNotIn lists', () {
        const filter = QueryFilter(
          field: 'a',
          whereIn: [1, 2],
          whereNotIn: [3],
        );
        expect(filter.matches({'a': 1}), isTrue);
        expect(filter.matches({'a': 3}), isFalse);
        expect(filter.matches({'a': 4}), isFalse);
      });
    });
  });
}
