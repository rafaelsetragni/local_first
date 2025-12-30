part of '../../local_first.dart';

/// Utility for generating UUIDs.
sealed class UuidUtil {
  UuidUtil._();

  static final Random _rand = Random.secure();

  /// Generates a UUIDv7 string (time-ordered).
  ///
  /// Layout (big endian):
  /// - 48 bits: unix epoch millis
  /// - 4 bits: version (0b0111)
  /// - 12 bits: random
  /// - 2 bits: variant (10)
  /// - 62 bits: random
  static String generateUuidV7() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;

    // 16 bytes buffer
    final bytes = Uint8List(16);

    // Timestamp 48 bits
    bytes[0] = (ms >> 40) & 0xff;
    bytes[1] = (ms >> 32) & 0xff;
    bytes[2] = (ms >> 24) & 0xff;
    bytes[3] = (ms >> 16) & 0xff;
    bytes[4] = (ms >> 8) & 0xff;
    bytes[5] = ms & 0xff;

    // 12 bits random (rand_a)
    final randA = _rand.nextInt(1 << 12);
    // version 7 in high nibble
    bytes[6] = 0x70 | ((randA >> 8) & 0x0f);
    bytes[7] = randA & 0xff;

    // Remaining 62 bits random (rand_b)
    for (var i = 8; i < 16; i++) {
      bytes[i] = _rand.nextInt(256);
    }
    // Variant: 10xx....
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
