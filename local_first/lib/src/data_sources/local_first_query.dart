part of '../../local_first.dart';

/// Represents a query with filters and sorting.
///
/// Provides a fluent API for building complex queries with filtering,
/// ordering, and pagination capabilities.
class LocalFirstQuery<T> {
  final String repositoryName;
  final List<QueryFilter> filters;
  final List<QuerySort> sorts;
  final int? limit;
  final int? offset;
  final LocalFirstStorage _delegate;
  final T Function(Map<String, dynamic>) _fromJson;
  final LocalFirstRepository<T> _repository;

  LocalFirstQuery({
    required this.repositoryName,
    required LocalFirstStorage delegate,
    required T Function(Map<String, dynamic>) fromJson,
    required LocalFirstRepository<T> repository,
    this.filters = const [],
    this.sorts = const [],
    this.limit,
    this.offset,
  }) : _delegate = delegate,
       _fromJson = fromJson,
       _repository = repository;

  LocalFirstQuery<T> copyWith({
    List<QueryFilter>? filters,
    List<QuerySort>? sorts,
    int? limit,
    int? offset,
  }) {
    return LocalFirstQuery<T>(
      repositoryName: repositoryName,
      delegate: _delegate,
      fromJson: _fromJson,
      repository: _repository,
      filters: filters ?? this.filters,
      sorts: sorts ?? this.sorts,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  /// Adds a filter condition to the query.
  ///
  /// Multiple filters can be chained and will be combined with AND logic.
  ///
  /// Example:
  /// ```dart
  /// query()
  ///   .where('age', isGreaterThan: 18)
  ///   .where('status', isEqualTo: 'active')
  /// ```
  LocalFirstQuery<T> where(
    String field, {
    dynamic isEqualTo,
    dynamic isNotEqualTo,
    dynamic isLessThan,
    dynamic isLessThanOrEqualTo,
    dynamic isGreaterThan,
    dynamic isGreaterThanOrEqualTo,
    List<dynamic>? whereIn,
    List<dynamic>? whereNotIn,
    bool? isNull,
  }) {
    final filter = QueryFilter(
      field: field,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
      isNull: isNull,
    );

    return copyWith(filters: [...filters, filter]);
  }

  /// Adds sorting to the query.
  ///
  /// Multiple sorts can be chained for secondary sorting.
  ///
  /// Parameters:
  /// - [field]: The field name to sort by
  /// - [descending]: If true, sorts in descending order (default: false)
  ///
  /// Example:
  /// ```dart
  /// query().orderBy('createdAt', descending: true)
  /// ```
  LocalFirstQuery<T> orderBy(String field, {bool descending = false}) {
    final sort = QuerySort(field: field, descending: descending);
    return copyWith(sorts: [...sorts, sort]);
  }

  /// Limits the number of results returned.
  ///
  /// Example:
  /// ```dart
  /// query().limitTo(10)  // Returns max 10 results
  /// ```
  LocalFirstQuery<T> limitTo(int count) {
    return copyWith(limit: count);
  }

  /// Skips the first N results (pagination offset).
  ///
  /// Example:
  /// ```dart
  /// query().startAfter(10).limitTo(10)  // Gets results 11-20
  /// ```
  LocalFirstQuery<T> startAfter(int count) {
    return copyWith(offset: count);
  }

  /// Executes the query and returns all matching results.
  ///
  /// Returns a list of models with sync metadata.
  Future<List<LocalFirstEvent<T>>> getAll() async {
    final results = await _delegate.query(this);
    return _mapResults(results);
  }

  /// Returns a reactive stream of query results.
  ///
  /// The stream will emit new values whenever the underlying data changes.
  ///
  /// Example:
  /// ```dart
  /// query()
  ///   .where('status', isEqualTo: 'active')
  ///   .watch()
  ///   .listen((items) => print('Active items: ${items.length}'));
  /// ```
  Stream<List<LocalFirstEvent<T>>> watch() {
    return _delegate.watchQuery(this).map(_mapResults).asBroadcastStream();
  }

  List<LocalFirstEvent<T>> _mapResults(List<Map<String, dynamic>> results) {
    return results
        .map((json) {
          final itemJson = Map<String, dynamic>.from(json);
          final item = _fromJson(
            itemJson..removeWhere((key, _) => key.startsWith('_sync_')),
          );

          // Extract sync metadata stored alongside the model
          final syncStatus = json['_sync_status'] != null
              ? SyncStatus.values[json['_sync_status'] as int]
              : SyncStatus.ok;

          final syncOperation = json['_sync_operation'] != null
              ? SyncOperation.values[json['_sync_operation'] as int]
              : SyncOperation.insert;

          final createdAt = json['_sync_created_at'] as int?;
          final createdAtDate = createdAt != null
              ? DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true)
              : null;

          return LocalFirstEvent<T>(
            payload: item,
            syncStatus: syncStatus,
            syncOperation: syncOperation,
            syncCreatedAt: createdAtDate,
            repositoryName: repositoryName,
          );
        })
        .where((obj) => !obj.isDeleted)
        .toList();
  }
}

/// Represents an individual filter condition.
///
/// Filters are used to select specific items based on field values.
class QueryFilter {
  final String field;
  final dynamic isEqualTo;
  final dynamic isNotEqualTo;
  final dynamic isLessThan;
  final dynamic isLessThanOrEqualTo;
  final dynamic isGreaterThan;
  final dynamic isGreaterThanOrEqualTo;
  final List<dynamic>? whereIn;
  final List<dynamic>? whereNotIn;
  final bool? isNull;

  const QueryFilter({
    required this.field,
    this.isEqualTo,
    this.isNotEqualTo,
    this.isLessThan,
    this.isLessThanOrEqualTo,
    this.isGreaterThan,
    this.isGreaterThanOrEqualTo,
    this.whereIn,
    this.whereNotIn,
    this.isNull,
  });

  /// Checks if an item matches this filter (fallback for DBs without native query support).
  bool matches(Map<String, dynamic> item) {
    final value = item[field];

    if (isNull != null) {
      return (value == null) == isNull;
    }

    if (isEqualTo != null && value != isEqualTo) return false;
    if (isNotEqualTo != null && value == isNotEqualTo) return false;

    if (isLessThan != null) {
      if (value is! Comparable || !(value.compareTo(isLessThan) < 0)) {
        return false;
      }
    }

    if (isLessThanOrEqualTo != null) {
      if (value is! Comparable ||
          !(value.compareTo(isLessThanOrEqualTo) <= 0)) {
        return false;
      }
    }

    if (isGreaterThan != null) {
      if (value is! Comparable || !(value.compareTo(isGreaterThan) > 0)) {
        return false;
      }
    }

    if (isGreaterThanOrEqualTo != null) {
      if (value is! Comparable ||
          !(value.compareTo(isGreaterThanOrEqualTo) >= 0)) {
        return false;
      }
    }

    if (whereIn != null && !whereIn!.contains(value)) return false;
    if (whereNotIn != null && whereNotIn!.contains(value)) return false;

    return true;
  }
}

/// Represents a sort order for query results.
///
/// Defines how results should be ordered by a specific field.
class QuerySort {
  /// The field name to sort by.
  final String field;

  /// If true, sorts in descending order (default: ascending).
  final bool descending;

  const QuerySort({required this.field, this.descending = false});
}
