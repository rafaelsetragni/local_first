part of '../../local_first.dart';

/// Generates unique IDs for local events.
sealed class IdUtil {
  static final Random _random = Random.secure();

  /// The millisecond the last id was minted in, and its counter.
  static int _lastMillis = -1;
  static int _counter = 0;

  /// The counter's 12 bits (`rand_a`, RFC 9562 §6.2, method 1).
  static const int _counterMax = 0xfff;

  /// Generates a UUID v7 (time-ordered, 36-char with hyphens).
  ///
  /// Ids minted by this process are strictly increasing, also within one
  /// millisecond: `rand_a` carries a counter that starts at a random value in
  /// its lower half each new millisecond and grows by one inside it. Pending
  /// writes are sent in the order of their ids, so two writes made in the same
  /// millisecond — a create and the edit after it — must never swap. When the
  /// counter is spent, or the clock steps back, the id borrows the next
  /// millisecond instead of going backwards.
  static String uuidV7() {
    var timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (timestamp > _lastMillis) {
      _counter = _random.nextInt((_counterMax + 1) ~/ 2);
    } else {
      timestamp = _lastMillis;
      _counter++;
      if (_counter > _counterMax) {
        timestamp++;
        _counter = _random.nextInt((_counterMax + 1) ~/ 2);
      }
    }
    _lastMillis = timestamp;

    final bytes = List<int>.filled(16, 0);

    // 48-bit timestamp, big endian
    bytes[0] = (timestamp >> 40) & 0xff;
    bytes[1] = (timestamp >> 32) & 0xff;
    bytes[2] = (timestamp >> 24) & 0xff;
    bytes[3] = (timestamp >> 16) & 0xff;
    bytes[4] = (timestamp >> 8) & 0xff;
    bytes[5] = timestamp & 0xff;

    // version (7) and the 12-bit counter
    bytes[6] = 0x70 | ((_counter >> 8) & 0x0f);
    bytes[7] = _counter & 0xff;

    for (var i = 8; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }
    // variant (10xxxxxx)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
