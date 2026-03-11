import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/widgets.dart';
import 'package:local_first/local_first.dart';
import 'package:shared_preferences/shared_preferences.dart';

  /// Simple config storage backed by `shared_preferences`, with all keys
  /// automatically prefixed by a namespace so different users/sessions stay
  /// isolated.
  ///
  /// When [password] is provided, all values are AES-256 encrypted before being
  /// stored. The encryption key is derived from the password using SHA-256.
class SharedPreferencesConfigStorage implements ConfigKeyValueStorage {
  SharedPreferencesConfigStorage({
    String namespace = 'default',
    String? password,
  }) : _namespace = namespace.isEmpty ? 'default' : namespace,
       _password = password;

  SharedPreferences? _prefs;
  bool _initialized = false;
  String _namespace;
  final String? _password;

  enc.Encrypter? _encrypter;
  enc.IV? _iv;

  bool get _isEncrypted => _password != null;

  /// Current namespace prefix applied to all keys.
  String get namespace => _namespace;

  SharedPreferences _prefsOrThrow() {
    final prefs = _prefs;
    if (!_initialized || prefs == null) {
      throw StateError(
        'SharedPreferencesConfigStorage not initialized. Call initialize() first.',
      );
    }
    return prefs;
  }

  String _key(String key) => '$_namespace::$key';

  void _initCrypto() {
    if (_password == null) return;
    final keyBytes = sha256.convert(utf8.encode(_password)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    _iv = enc.IV(Uint8List.fromList(keyBytes.sublist(0, 16)));
    _encrypter = enc.Encrypter(enc.AES(key));
  }

  String _encryptValue(String plaintext) {
    return _encrypter!.encrypt(plaintext, iv: _iv).base64;
  }

  String _decryptValue(String ciphertext) {
    return _encrypter!.decrypt64(ciphertext, iv: _iv);
  }

  String _encodeTypedValue(Object value) {
    if (value is bool) return jsonEncode({'t': 'bool', 'v': value});
    if (value is int) return jsonEncode({'t': 'int', 'v': value});
    if (value is double) return jsonEncode({'t': 'double', 'v': value});
    if (value is String) return jsonEncode({'t': 'string', 'v': value});
    if (value is List && value.every((e) => e is String)) {
      return jsonEncode({'t': 'string_list', 'v': List<String>.from(value)});
    }
    throw ArgumentError(
      'Unsupported config value type ${value.runtimeType}. '
      'Allowed: bool, int, double, String, List<String>.',
    );
  }

  T? _decodeTypedValue<T>(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['t'] as String?;
      final value = decoded['v'];
      switch (type) {
        case 'bool':
          return value is bool && (T == bool || T == dynamic) ? value as T : null;
        case 'int':
          return value is int && (T == int || T == dynamic) ? value as T : null;
        case 'double':
          if (value is num && (T == double || T == dynamic)) return value.toDouble() as T;
          return null;
        case 'string':
          return value is String && (T == String || T == dynamic) ? value as T : null;
        case 'string_list':
          if (value is List && (T == dynamic || T == List<String>)) {
            return List<String>.from(value) as T;
          }
          return null;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Prepares the `SharedPreferences` instance so reads and writes can happen.
  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();
    _initCrypto();
    _initialized = true;
  }

  /// Resets the adapter and drops the cached prefs instance.
  @override
  Future<void> close() async {
    _prefs = null;
    _initialized = false;
  }

  /// Switches the namespace prefix used for every key/value pair.
  ///
  /// - [namespace]: Logical bucket name (for example, a user id). Empty strings
  ///   fall back to `default` so callers never create a blank prefix.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;
    _namespace = namespace.isEmpty ? 'default' : namespace;
  }

  /// Checks if a namespaced config key already exists.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> containsConfigKey(String key) async {
    final prefs = _prefsOrThrow();
    return prefs.containsKey(_key(key));
  }

  /// Saves a config value under the current namespace.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  /// - [value]: Allowed types: bool, int, double, String or `List<String>`. Any
  ///   other type triggers an [ArgumentError].
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    final prefs = _prefsOrThrow();
    if (value is! Object) {
      throw ArgumentError('Config value cannot be null.');
    }
    final namespacedKey = _key(key);

    if (_isEncrypted) {
      final encoded = _encodeTypedValue(value);
      final encrypted = _encryptValue(encoded);
      return prefs.setString(namespacedKey, encrypted);
    }

    if (value is bool) return prefs.setBool(namespacedKey, value);
    if (value is int) return prefs.setInt(namespacedKey, value);
    if (value is double) return prefs.setDouble(namespacedKey, value);
    if (value is String) return prefs.setString(namespacedKey, value);
    if (value is List<String>) {
      return prefs.setStringList(namespacedKey, List<String>.from(value));
    }
    if (value is List && value.every((e) => e is String)) {
      return prefs.setStringList(
        namespacedKey,
        List<String>.from(value.map((e) => e as String)),
      );
    }
    throw ArgumentError(
      'Unsupported config value type ${value.runtimeType}. '
      'Allowed: bool, int, double, String, List<String>.',
    );
  }

  /// Reads a config value for the given key.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<T?> getConfigValue<T>(String key) async {
    final prefs = _prefsOrThrow();
    final namespacedKey = _key(key);

    if (_isEncrypted) {
      final raw = prefs.getString(namespacedKey);
      if (raw == null) return null;
      final decrypted = _decryptValue(raw);
      return _decodeTypedValue<T>(decrypted);
    }

    final value = prefs.get(namespacedKey);
    if (value == null) return null;
    if (T == dynamic) return value as T;
    if (value is List<String>) {
      if (value is T) return value as T;
      return null;
    }
    if (value is T) return value as T;
    return null;
  }

  /// Deletes a single config entry from the current namespace.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> removeConfig(String key) async {
    final prefs = _prefsOrThrow();
    return prefs.remove(_key(key));
  }

  /// Wipes every config entry stored in the current namespace.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> clearConfig() async {
    final prefs = _prefsOrThrow();
    final keys = prefs.getKeys().where((k) => k.startsWith('$_namespace::'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    return true;
  }

  /// Lists all config keys for the active namespace.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<Set<String>> getConfigKeys() async {
    final prefs = _prefsOrThrow();
    final prefix = '$_namespace::';
    return prefs
        .getKeys()
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toSet();
  }
}
