import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  test('generateUuidV7 returns valid version and variant', () {
    final id = UuidUtil.generateUuidV7();

    final parts = id.split('-');
    expect(parts.length, 5);
    expect(parts[0].length, 8);
    expect(parts[1].length, 4);
    expect(parts[2].length, 4);
    expect(parts[3].length, 4);
    expect(parts[4].length, 12);

    // version nibble is the first char of the 3rd group.
    expect(parts[2][0], '7');

    // variant must be 8, 9, a, or b.
    final variant = parts[3][0].toLowerCase();
    expect(['8', '9', 'a', 'b'], contains(variant));
  });

  test('generateUuidV7 is time ordered and mostly unique', () {
    const count = 200;
    final ids = <String>{};
    for (var i = 0; i < count; i++) {
      ids.add(UuidUtil.generateUuidV7());
    }

    // IDs should be unique in this small sample.
    expect(ids.length, count);

    // Timestamp segment (first 48 bits) should be non-decreasing.
    int parseTimestamp(String id) {
      final parts = id.split('-');
      final tsHex = parts[0] + parts[1];
      return int.parse(tsHex, radix: 16);
    }

    var lastTs = parseTimestamp(ids.first);
    for (final id in ids.skip(1)) {
      final ts = parseTimestamp(id);
      expect(ts >= lastTs, isTrue);
      lastTs = ts;
    }
  });
}
