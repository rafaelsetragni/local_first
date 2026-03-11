import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('IdUtil.uuidV7', () {
    test('should generate 36-char UUID with hyphens', () {
      final id = IdUtil.uuidV7();

      expect(id.length, 36);
      expect(id[8], '-');
      expect(id[13], '-');
      expect(id[18], '-');
      expect(id[23], '-');
    });

    test('should set version to 7', () {
      final id = IdUtil.uuidV7();
      final versionChar = id[14];

      expect(versionChar, '7');
    });

    test('should set variant to 10xxxxxx', () {
      final id = IdUtil.uuidV7();
      final variantChar = id[19].toLowerCase();
      final variant = int.parse(variantChar, radix: 16);

      expect((variant & 0x8), isPositive); // high bit set
    });

    test('should produce lexicographically increasing ids over time', () async {
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        ids.add(IdUtil.uuidV7());
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      for (var i = 0; i < ids.length - 1; i++) {
        expect(ids[i].compareTo(ids[i + 1]) < 0, isTrue);
      }
    });

    test('should generate unique ids across multiple calls', () {
      final count = 1000;
      final ids = <String>{};
      for (var i = 0; i < count; i++) {
        ids.add(IdUtil.uuidV7());
      }
      expect(ids.length, count);
    });
  });
}
