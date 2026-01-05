import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('LocalFirstMemoryKeyValueStorage - lifecycle', () {
    test('throws when not open', () async {
      final s = LocalFirstMemoryKeyValueStorage();
      expect(s.isOpen, isFalse);
      expect(() => s.get('x'), throwsStateError);
      await s.open(namespace: 'ns');
      expect(s.isOpen, isTrue);
    });

    test('open/close toggles state and namespace', () async {
      final s = LocalFirstMemoryKeyValueStorage();
      expect(s.isOpen, isFalse);

      await s.open(namespace: 'ns1');
      expect(s.isOpen, isTrue);
      await s.set('k', 'v');
      expect(await s.get<String>('k'), 'v');

      await s.close();
      expect(s.isOpen, isFalse);
      expect(() => s.get('k'), throwsStateError);
    });

    test('separate namespaces do not clash', () async {
      final s = LocalFirstMemoryKeyValueStorage();
      await s.open(namespace: 'a');
      await s.set('k', 'v1');
      await s.close();

      await s.open(namespace: 'b');
      expect(await s.get<String>('k'), isNull);
      await s.set('k', 'v2');
      expect(await s.get<String>('k'), 'v2');

      await s.close();
      await s.open(namespace: 'a');
      expect(await s.get<String>('k'), 'v1');
    });
  });

  group('LocalFirstMemoryKeyValueStorage - supported types', () {
    late LocalFirstMemoryKeyValueStorage storage;

    setUp(() async {
      storage = LocalFirstMemoryKeyValueStorage();
      await storage.open();
    });

    test('stores and retrieves String', () async {
      await storage.set('k', 'v');
      expect(await storage.get<String>('k'), 'v');
    });

    test('stores and retrieves int', () async {
      await storage.set('k', 42);
      expect(await storage.get<int>('k'), 42);
    });

    test('stores and retrieves double', () async {
      await storage.set('k', 3.14);
      expect(await storage.get<double>('k'), 3.14);
    });

    test('stores and retrieves bool', () async {
      await storage.set('k', true);
      expect(await storage.get<bool>('k'), true);
    });

    test('stores and retrieves List<String>', () async {
      await storage.set('k', ['a', 'b']);
      expect(await storage.get<List<String>>('k'), ['a', 'b']);
    });

    test('delete removes key', () async {
      await storage.set('k', 'v');
      await storage.delete('k');
      expect(await storage.get<String>('k'), isNull);
    });

    test('rejects Map', () async {
      expect(() => storage.set('k', {'a': 'b'}), throwsArgumentError);
    });

    test('rejects List<int>', () async {
      expect(() => storage.set('k', [1, 2, 3]), throwsArgumentError);
    });
  });
}
