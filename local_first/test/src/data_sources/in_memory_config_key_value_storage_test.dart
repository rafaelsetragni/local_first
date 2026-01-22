import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('InMemoryConfigKeyValueStorage', () {
    late InMemoryConfigKeyValueStorage storage;

    setUp(() async {
      storage = InMemoryConfigKeyValueStorage();
      await storage.initialize();
    });

    test('requires initialization', () async {
      final fresh = InMemoryConfigKeyValueStorage();
      expect(() => fresh.setConfigValue('k', 'v'), throwsStateError);
      expect(() => fresh.getConfigValue('k'), throwsStateError);
    });

    test('returns null when key is missing', () async {
      expect(await storage.getConfigValue<String>('missing'), isNull);
    });

    test('uses namespaces to isolate values', () async {
      await storage.setConfigValue('k', 'v1');
      await storage.useNamespace('other');
      expect(await storage.getConfigValue<String>('k'), isNull);
      await storage.setConfigValue('k', 'v2');
      await storage.useNamespace('default');
      expect(await storage.getConfigValue<String>('k'), 'v1');
    });

    test('stores and retrieves supported types', () async {
      await storage.setConfigValue('bool', true);
      await storage.setConfigValue('int', 1);
      await storage.setConfigValue('double', 2.5);
      await storage.setConfigValue('string', 'ok');
      await storage.setConfigValue('list', ['a', 'b']);

      expect(await storage.getConfigValue<bool>('bool'), isTrue);
      expect(await storage.getConfigValue<int>('int'), 1);
      expect(await storage.getConfigValue<double>('double'), 2.5);
      expect(await storage.getConfigValue<String>('string'), 'ok');
      expect(await storage.getConfigValue<List<String>>('list'), ['a', 'b']);
      expect(await storage.getConfigValue<dynamic>('list'), ['a', 'b']);
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
      expect(() => storage.setConfigValue('null', null), throwsArgumentError);
    });

    test('removes and clears keys', () async {
      await storage.setConfigValue('k', 'v');
      expect(await storage.removeConfig('k'), isTrue);
      expect(await storage.containsConfigKey('k'), isFalse);

      await storage.setConfigValue('k2', 'v2');
      expect(await storage.clearConfig(), isTrue);
      expect(await storage.getConfigKeys(), isEmpty);
    });

    test('closes and clears internal state', () async {
      await storage.setConfigValue('k', 'v');
      await storage.close();
      expect(() => storage.setConfigValue('k', 'v'), throwsStateError);
      await storage.initialize();
      expect(await storage.getConfigKeys(), isEmpty);
    });
  });
}
