part of '../../local_first.dart';

/// Represents a query with filters and sorting.
///
/// Concrete storage backends must apply filtering/sorting; this class only
/// carries the query shape and delegates execution.
class LocalFirstQuery<T> {
  final String repositoryName;
  final List<QueryFilter> filters;
  final List<QuerySort> sorts;
  final int? limit;
  final int? offset;
  final bool includeDeleted;
  final LocalFirstStorage _delegate;
  final LocalFirstRepository<T> _repository;

  LocalFirstRepository<T> get repository => _repository;

  LocalFirstQuery({
    required this.repositoryName,
    required LocalFirstStorage delegate,
    required LocalFirstRepository<T> repository,
    this.filters = const [],
    this.sorts = const [],
    this.limit,
    this.offset,
    this.includeDeleted = false,
  }) : _delegate = delegate,
       _repository = repository;

  LocalFirstQuery<T> copyWith({
    List<QueryFilter>? filters,
    List<QuerySort>? sorts,
    int? limit,
    int? offset,
    bool? includeDeleted,
  }) {
    return LocalFirstQuery<T>(
      repositoryName: repositoryName,
      delegate: _delegate,
      repository: _repository,
      filters: filters ?? this.filters,
      sorts: sorts ?? this.sorts,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      includeDeleted: includeDeleted ?? this.includeDeleted,
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

  /// Includes soft-deleted items (delete events) in results.
  LocalFirstQuery<T> withDeleted({bool include = true}) {
    return copyWith(includeDeleted: include);
  }

  /// Executes the query and returns all matching results.
  ///
  /// Storage backends are responsible for applying filters/sorts and
  /// hydrating events.
  Future<List<LocalFirstEvent<T>>> getAll() async {
    return _delegate.query<T>(this);
  }

  /// Returns a reactive stream of query results.
  ///
  /// The stream will emit new values whenever the underlying data changes.
  Stream<List<LocalFirstEvent<T>>> watch() {
    return _delegate.watchQuery<T>(this);
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
  bool matches(JsonMap item) {
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
