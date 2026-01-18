part of '../../local_first.dart';

/// Generates unique IDs for local events.
sealed class IdUtil {
  /// Generates a UUID v7-like identifier (time-ordered, 36-char with hyphens).
  static String uuidV7() {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final rand = Random.secure();
    final bytes = List<int>.filled(16, 0);

    // 48-bit timestamp, big endian
    bytes[0] = (timestamp >> 40) & 0xff;
    bytes[1] = (timestamp >> 32) & 0xff;
    bytes[2] = (timestamp >> 24) & 0xff;
    bytes[3] = (timestamp >> 16) & 0xff;
    bytes[4] = (timestamp >> 8) & 0xff;
    bytes[5] = timestamp & 0xff;

    for (var i = 6; i < 16; i++) {
      bytes[i] = rand.nextInt(256);
    }

    // Set version (7)
    bytes[6] = (bytes[6] & 0x0f) | 0x70;
    // Set variant (10xxxxxx)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
