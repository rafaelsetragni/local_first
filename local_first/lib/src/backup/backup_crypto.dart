import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as aes;

/// Handles encryption, decryption, and compression for backup files.
///
/// Pipeline:
/// - **Export:** JSON string → UTF-8 → gzip → AES-256-CBC → `.lfbk` binary
/// - **Import:** `.lfbk` binary → AES-256 decrypt → gunzip → UTF-8 → JSON
///
/// Key derivation uses PBKDF2-HMAC-SHA256 with a random 16-byte salt.
/// The output format is: `salt (16 bytes) + IV (16 bytes) + ciphertext`.
class BackupCrypto {
  static const int _saltLength = 16;
  static const int _ivLength = 16;
  static const int _keyLength = 32; // AES-256
  static const int _iterations = 100000;

  /// Compresses and encrypts [plainBytes] with [password].
  ///
  /// Returns the encrypted bytes with salt and IV prepended.
  static List<int> encryptBytes(List<int> plainBytes, String password) {
    // Compress
    final compressed = gzip.encode(plainBytes);

    // Generate random salt and IV
    final random = Random.secure();
    final salt = Uint8List(_saltLength);
    final iv = Uint8List(_ivLength);
    for (var i = 0; i < _saltLength; i++) {
      salt[i] = random.nextInt(256);
    }
    for (var i = 0; i < _ivLength; i++) {
      iv[i] = random.nextInt(256);
    }

    // Derive key via PBKDF2
    final key = _deriveKey(password, salt);

    // Encrypt with AES-256-CBC
    final encrypter = aes.Encrypter(
      aes.AES(aes.Key(key), mode: aes.AESMode.cbc),
    );
    final encrypted = encrypter.encryptBytes(
      compressed,
      iv: aes.IV(iv),
    );

    // Output: salt + IV + ciphertext
    return [...salt, ...iv, ...encrypted.bytes];
  }

  /// Decrypts and decompresses [cipherBytes] with [password].
  ///
  /// Throws [ArgumentError] if the data is too short.
  /// Throws [FormatException] if the password is wrong or data is corrupted.
  static List<int> decryptBytes(List<int> cipherBytes, String password) {
    final minLength = _saltLength + _ivLength + 1;
    if (cipherBytes.length < minLength) {
      throw ArgumentError(
        'Backup data too short (${cipherBytes.length} bytes, need at least $minLength)',
      );
    }

    // Extract salt, IV, ciphertext
    final data = Uint8List.fromList(cipherBytes);
    final salt = data.sublist(0, _saltLength);
    final iv = data.sublist(_saltLength, _saltLength + _ivLength);
    final ciphertext = data.sublist(_saltLength + _ivLength);

    // Derive key via PBKDF2
    final key = _deriveKey(password, salt);

    // Decrypt
    final encrypter = aes.Encrypter(
      aes.AES(aes.Key(key), mode: aes.AESMode.cbc),
    );

    final List<int> compressed;
    try {
      compressed = encrypter.decryptBytes(
        aes.Encrypted(ciphertext),
        iv: aes.IV(iv),
      );
    } catch (e) {
      throw FormatException(
        'Failed to decrypt backup. Wrong password or corrupted data.',
      );
    }

    // Decompress
    try {
      return gzip.decode(compressed);
    } catch (e) {
      throw FormatException(
        'Failed to decompress backup. Wrong password or corrupted data.',
      );
    }
  }

  /// Convenience: encrypts a JSON-serializable map.
  static List<int> encryptJson(Map<String, dynamic> json, String password) {
    final jsonString = jsonEncode(json);
    final plainBytes = utf8.encode(jsonString);
    return encryptBytes(plainBytes, password);
  }

  /// Convenience: decrypts bytes back to a JSON map.
  static Map<String, dynamic> decryptJson(
    List<int> cipherBytes,
    String password,
  ) {
    final plainBytes = decryptBytes(cipherBytes, password);
    final jsonString = utf8.decode(plainBytes);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  /// PBKDF2-HMAC-SHA256 key derivation.
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    final hmacSha256 = Hmac(sha256, passwordBytes);

    // PBKDF2 block 1 (we only need 32 bytes = 1 block for SHA-256)
    final block1Salt = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = hmacSha256.convert(block1Salt).bytes;
    var result = Uint8List.fromList(u);

    for (var i = 1; i < _iterations; i++) {
      u = hmacSha256.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }

    return result.sublist(0, _keyLength);
  }
}
