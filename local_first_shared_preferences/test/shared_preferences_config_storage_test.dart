import 'package:flutter_test/flutter_test.dart';
import 'package:local_first_shared_preferences/local_first_shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesConfigStorage', () {
    late SharedPreferencesConfigStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = SharedPreferencesConfigStorage();
      await storage.initialize();
    });

    test('exposes current namespace and updates when changed', () async {
      expect(storage.namespace, 'default');
      await storage.useNamespace('user_ns');
      expect(storage.namespace, 'user_ns');
    });

    test('requires initialization', () async {
      final fresh = SharedPreferencesConfigStorage();
      expect(() => fresh.setConfigValue('k', 'v'), throwsStateError);
      expect(() => fresh.getConfigValue('k'), throwsStateError);
    });

    test('stores and retrieves supported types', () async {
      await storage.setConfigValue('bool', true);
      await storage.setConfigValue('int', 1);
      await storage.setConfigValue('double', 2.5);
      await storage.setConfigValue('string', 'ok');
      await storage.setConfigValue('list', ['a', 'b']);
      await storage.setConfigValue('dynList', <dynamic>['c', 'd']);

      expect(await storage.getConfigValue<bool>('bool'), isTrue);
      expect(await storage.getConfigValue<int>('int'), 1);
      expect(await storage.getConfigValue<double>('double'), 2.5);
      expect(await storage.getConfigValue<String>('string'), 'ok');
      expect(await storage.getConfigValue<List<String>>('list'), ['a', 'b']);
      expect(await storage.getConfigValue<dynamic>('list'), ['a', 'b']);
      expect(await storage.getConfigValue<List<String>>('dynList'), ['c', 'd']);
      expect(await storage.containsConfigKey('string'), isTrue);
      expect(
        await storage.getConfigKeys(),
        containsAll(['bool', 'int', 'double', 'string', 'list']),
      );
    });

    test('rejects unsupported types and null values', () async {
      expect(
        () => storage.setConfigValue('bad', {'a': 1}),
        throwsArgumentError,
      );
      expect(
        () => storage.setConfigValue('bad', ['a', 1]),
        throwsArgumentError,
      );
      expect(() => storage.setConfigValue('null', null), throwsArgumentError);
    });

    test('removes and clears keys', () async {
      await storage.setConfigValue('k', 'v');
      expect(await storage.removeConfig('k'), isTrue);
      expect(await storage.containsConfigKey('k'), isFalse);

      await storage.setConfigValue('k2', 'v2');
      await storage.setConfigValue('k3', 'v3');
      expect(await storage.clearConfig(), isTrue);
      expect(await storage.getConfigKeys(), isEmpty);
    });

    test('uses namespaces to isolate values', () async {
      await storage.setConfigValue('k', 'v1');
      await storage.useNamespace('other');
      expect(await storage.getConfigValue<String>('k'), isNull);
      await storage.setConfigValue('k', 'v2');
      await storage.useNamespace('default');
      expect(await storage.getConfigValue<String>('k'), 'v1');
      expect(await storage.getConfigKeys(), contains('k'));
      await storage.useNamespace('other');
      expect(await storage.getConfigKeys(), contains('k'));
    });

    test('close resets initialization state', () async {
      await storage.close();
      expect(() => storage.getConfigValue('k'), throwsStateError);
    });
  });

  group('SharedPreferencesConfigStorage (encrypted)', () {
    late SharedPreferencesConfigStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = SharedPreferencesConfigStorage(password: 'test-secret-key');
      await storage.initialize();
    });

    test('stores and retrieves all supported types', () async {
      await storage.setConfigValue('bool', true);
      await storage.setConfigValue('int', 42);
      await storage.setConfigValue('double', 3.14);
      await storage.setConfigValue('string', 'encrypted');
      await storage.setConfigValue('list', <String>['a', 'b']);

      expect(await storage.getConfigValue<bool>('bool'), isTrue);
      expect(await storage.getConfigValue<int>('int'), 42);
      expect(await storage.getConfigValue<double>('double'), 3.14);
      expect(await storage.getConfigValue<String>('string'), 'encrypted');
      expect(await storage.getConfigValue<List<String>>('list'), ['a', 'b']);
      expect(await storage.getConfigValue<dynamic>('bool'), isTrue);
    });

    test('values are stored as encrypted strings in SharedPreferences',
        () async {
      await storage.setConfigValue('secret', 'plain-text');

      // Access raw SharedPreferences to verify encryption
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('default::secret');
      expect(raw, isNotNull);
      // The raw value should NOT be the plain text
      expect(raw, isNot('plain-text'));
      // It should be a base64-encoded encrypted blob
      expect(raw, isNot(contains('plain-text')));
    });

    test('rejects unsupported types', () async {
      expect(
        () => storage.setConfigValue('bad', {'a': 1}),
        throwsArgumentError,
      );
    });

    test('removes and clears keys', () async {
      await storage.setConfigValue('k', 'v');
      expect(await storage.removeConfig('k'), isTrue);
      expect(await storage.containsConfigKey('k'), isFalse);

      await storage.setConfigValue('k2', 'v2');
      await storage.setConfigValue('k3', 'v3');
      expect(await storage.clearConfig(), isTrue);
      expect(await storage.getConfigKeys(), isEmpty);
    });

    test('namespace isolation works with encryption', () async {
      await storage.setConfigValue('k', 'v1');
      await storage.useNamespace('other');
      expect(await storage.getConfigValue<String>('k'), isNull);
      await storage.setConfigValue('k', 'v2');
      await storage.useNamespace('default');
      expect(await storage.getConfigValue<String>('k'), 'v1');
    });

    test('dynamic list round-trips correctly', () async {
      await storage.setConfigValue('dynList', <dynamic>['c', 'd']);
      expect(
        await storage.getConfigValue<List<String>>('dynList'),
        ['c', 'd'],
      );
    });
  });
}
