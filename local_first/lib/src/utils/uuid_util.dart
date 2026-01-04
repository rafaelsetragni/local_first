part of '../../local_first.dart';

/// Utility helper to generate UUIDv7 identifiers.
sealed class UuidUtil {
  static final Random _random = Random.secure();

  /// Generates a UUID v7 string.
  ///
  /// Format: time-ordered with 48-bit timestamp and random payload,
  /// version set to 7 and variant RFC 4122.
  static String generateUuidV7() {
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;

    // 16-byte buffer
    final bytes = List<int>.filled(16, 0);

    // 48-bit timestamp (big-endian) into bytes[0..5]
    for (var i = 0; i < 6; i++) {
      bytes[5 - i] = (ts >> (8 * i)) & 0xff;
    }

    // random bytes for the rest
    for (var i = 6; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }

    // Set version (byte 6 high nibble)
    bytes[6] = (bytes[6] & 0x0f) | 0x70;
    // Set variant RFC 4122 (byte 8 high bits 10xx)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final b = bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).toList();
    return '${b[0]}${b[1]}${b[2]}${b[3]}'
        '-${b[4]}${b[5]}'
        '-${b[6]}${b[7]}'
        '-${b[8]}${b[9]}'
        '-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }
}
