part of '../../local_first.dart';

/// SharedPreferences-backed implementation of [LocalFirstKeyValueStorage].
class SharedPreferencesKeyValueStorage implements LocalFirstKeyValueStorage {
  SharedPreferences? _prefs;
  String _namespace = 'default';
  bool _opened = false;

  @override
  bool get isOpened => _opened;

  @override
  bool get isClosed => !_opened;

  @override
  String get currentNamespace => _namespace;

  @override
  Future<void> open({String namespace = 'default'}) async {
    _namespace = namespace;
    _prefs = await SharedPreferences.getInstance();
    _opened = true;
  }

  @override
  Future<void> close() async {
    _opened = false;
    _prefs = null;
  }

  @override
  Future<void> set<T>(String key, T value) async {
    final prefs = _ensureOpen();
    final namespaced = _namespacedKey(key);
    if (value is String) {
      await prefs.setString(namespaced, value);
      return;
    }
    if (value is bool) {
      await prefs.setBool(namespaced, value);
      return;
    }
    if (value is int) {
      await prefs.setInt(namespaced, value);
      return;
    }
    if (value is double) {
      await prefs.setDouble(namespaced, value);
      return;
    }
    if (value is List<String>) {
      await prefs.setStringList(namespaced, value);
      return;
    }
    throw ArgumentError('Unsupported value type for key "$key".');
  }

  @override
  Future<T?> get<T>(String key) async {
    final prefs = _ensureOpen();
    final value = prefs.get(_namespacedKey(key));
    if (value is T) {
      return value;
    }
    return null;
  }

  @override
  Future<bool> contains(String key) async {
    final prefs = _ensureOpen();
    return prefs.containsKey(_namespacedKey(key));
  }

  @override
  Future<void> delete(String key) async {
    final prefs = _ensureOpen();
    await prefs.remove(_namespacedKey(key));
  }

  SharedPreferences _ensureOpen() {
    final prefs = _prefs;
    if (!_opened || prefs == null) {
      throw StateError(
        'SharedPreferencesKeyValueStorage not open. Call open() first.',
      );
    }
    return prefs;
  }

  String _namespacedKey(String key) => '${_namespace}__$key';
}
