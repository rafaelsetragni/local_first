import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('JsonUtil.equals', () {
    test('identical references are equal', () {
      final map = {'a': 1};
      expect(JsonUtil.equals(map, map), isTrue);
    });

    test('null handling', () {
      expect(JsonUtil.equals(null, null), isTrue);
      expect(JsonUtil.equals(null, {}), isFalse);
      expect(JsonUtil.equals({}, null), isFalse);
    });

    test('primitive equality and inequality', () {
      expect(JsonUtil.equals(1, 1), isTrue);
      expect(JsonUtil.equals('x', 'x'), isTrue);
      expect(JsonUtil.equals(1, 2), isFalse);
      expect(JsonUtil.equals('x', 'y'), isFalse);
    });

    test('map equality is structural and order independent', () {
      final left = {'a': 1, 'b': 2};
      final right = {'b': 2, 'a': 1};
      expect(JsonUtil.equals(left, right), isTrue);
    });

    test('map inequality on keys and values', () {
      expect(JsonUtil.equals({'a': 1}, {'a': 2}), isFalse);
      expect(JsonUtil.equals({'a': 1}, {'b': 1}), isFalse);
    });

    test('list equality is structural and ordered', () {
      expect(JsonUtil.equals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(JsonUtil.equals([1, 2, 3], [3, 2, 1]), isFalse);
    });

    test('nested map/list structures', () {
      final left = {
        'a': [
          {'x': 1},
          {'y': [1, 2]}
        ],
        'b': 'ok',
      };
      final right = {
        'b': 'ok',
        'a': [
          {'x': 1},
          {'y': [1, 2]}
        ],
      };

      expect(JsonUtil.equals(left, right), isTrue);
    });

    test('nested mismatch detected', () {
      final left = {
        'a': [
          {'x': 1},
          {'y': [1, 2]}
        ],
        'b': 'ok',
      };
      final right = {
        'a': [
          {'x': 1},
          {'y': [2, 1]}
        ],
        'b': 'ok',
      };

      expect(JsonUtil.equals(left, right), isFalse);
    });
  });
}
