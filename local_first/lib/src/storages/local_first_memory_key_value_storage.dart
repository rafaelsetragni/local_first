part of '../../local_first.dart';

/// In-memory implementation of [LocalFirstKeyValueStorage] for tests/dev.
class LocalFirstMemoryKeyValueStorage implements LocalFirstKeyValueStorage {
  final Map<String, Map<String, dynamic>> _store = {};
  String? _namespace;

  @override
  Future<void> open({String namespace = 'default'}) async {
    _namespace = namespace;
    _store.putIfAbsent(namespace, () => {});
  }

  @override
  bool get isOpen => _namespace != null;

  @override
  Future<void> set<T>(String key, T value) async {
    final ns = _requireNamespace();
    _assertSupported(value);
    final bucket = _store[ns] ??= {};
    bucket[key] = value;
  }

  @override
  Future<T?> get<T>(String key) async {
    final ns = _requireNamespace();
    final value = _store[ns]?[key];
    if (value == null) return null;
    return value is T ? value : null;
  }

  @override
  Future<void> delete(String key) async {
    final ns = _requireNamespace();
    _store[ns]?.remove(key);
  }

  @override
  Future<void> close() async {
    _namespace = null;
  }

  String _requireNamespace() {
    final ns = _namespace;
    if (ns == null) {
      throw StateError('KeyValueStorage is not open. Call open() first.');
    }
    return ns;
  }

  void _assertSupported(dynamic value) {
    if (value == null ||
        value is String ||
        value is num ||
        value is bool) {
      return;
    }
    if (value is List<String>) return;
    throw ArgumentError('Unsupported value type: ${value.runtimeType}');
  }
}
