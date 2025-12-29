import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesKeyValueStorage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('open is required for operations', () async {
      final storage = SharedPreferencesKeyValueStorage();

      expect(() => storage.get<String>('k'), throwsA(isA<StateError>()));
      expect(() => storage.set('k', 'v'), throwsA(isA<StateError>()));
      expect(() => storage.contains('k'), throwsA(isA<StateError>()));
      expect(() => storage.delete('k'), throwsA(isA<StateError>()));
    });

    test('set/get supports shared preferences types', () async {
      final storage = SharedPreferencesKeyValueStorage();
      await storage.open();

      await storage.set('s', 'text');
      await storage.set('b', true);
      await storage.set('i', 7);
      await storage.set('d', 1.5);
      await storage.set('l', ['a', 'b']);

      expect(await storage.get<String>('s'), 'text');
      expect(await storage.get<bool>('b'), isTrue);
      expect(await storage.get<int>('i'), 7);
      expect(await storage.get<double>('d'), 1.5);
      expect(await storage.get<List<String>>('l'), ['a', 'b']);
    });

    test('set throws for unsupported value types', () async {
      final storage = SharedPreferencesKeyValueStorage();
      await storage.open();

      expect(
        () => storage.set('k', <String, String>{'a': 'b'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('get returns null when type does not match', () async {
      final storage = SharedPreferencesKeyValueStorage();
      await storage.open();

      await storage.set('i', 1);
      expect(await storage.get<String>('i'), isNull);
    });

    test('contains/delete reflect key lifecycle', () async {
      final storage = SharedPreferencesKeyValueStorage();
      await storage.open();

      expect(await storage.contains('k'), isFalse);
      await storage.set('k', 'v');
      expect(await storage.contains('k'), isTrue);
      await storage.delete('k');
      expect(await storage.contains('k'), isFalse);
    });

    test('contains/delete work per namespace', () async {
      final storage = SharedPreferencesKeyValueStorage();
      await storage.open(namespace: 'ns1');

      await storage.set('k', 'v1');
      expect(await storage.contains('k'), isTrue);

      await storage.delete('k');
      expect(await storage.contains('k'), isFalse);
    });

    test('namespaces do not collide', () async {
      final storage = SharedPreferencesKeyValueStorage();
      await storage.open(namespace: 'ns1');
      await storage.set('k', 'v1');

      await storage.open(namespace: 'ns2');
      await storage.set('k', 'v2');

      expect(await storage.get<String>('k'), 'v2');

      await storage.open(namespace: 'ns1');
      expect(await storage.get<String>('k'), 'v1');
    });

    test('open/close toggles state and preserves namespace', () async {
      final storage = SharedPreferencesKeyValueStorage();

      expect(storage.isOpened, isFalse);
      expect(storage.isClosed, isTrue);
      expect(storage.currentNamespace, 'default');

      await storage.open(namespace: 'ns1');
      expect(storage.isOpened, isTrue);
      expect(storage.isClosed, isFalse);
      expect(storage.currentNamespace, 'ns1');

      await storage.close();
      expect(storage.isOpened, isFalse);
      expect(storage.isClosed, isTrue);
      expect(storage.currentNamespace, 'ns1');
    });
  });
}
