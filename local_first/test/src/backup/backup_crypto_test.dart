import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/src/backup/backup_crypto.dart';

void main() {
  group('BackupCrypto', () {
    const password = 'test-password-123';
    const wrongPassword = 'wrong-password';

    test('encrypt/decrypt roundtrip preserves data', () {
      final original = utf8.encode('Hello, World! This is a backup test.');
      final encrypted = BackupCrypto.encryptBytes(original, password);
      final decrypted = BackupCrypto.decryptBytes(encrypted, password);

      expect(decrypted, equals(original));
    });

    test('encrypt/decrypt roundtrip with large data', () {
      // Generate ~10KB of data
      final original = utf8.encode(
        List.generate(1000, (i) => 'item_$i: value_$i').join('\n'),
      );
      final encrypted = BackupCrypto.encryptBytes(original, password);
      final decrypted = BackupCrypto.decryptBytes(encrypted, password);

      expect(decrypted, equals(original));
    });

    test('encrypt/decrypt JSON roundtrip', () {
      final originalJson = {
        'version': 1,
        'data': [
          {'id': '1', 'name': 'Alice'},
          {'id': '2', 'name': 'Bob'},
        ],
        'config': {'key': 'value'},
      };

      final encrypted = BackupCrypto.encryptJson(originalJson, password);
      final decrypted = BackupCrypto.decryptJson(encrypted, password);

      expect(decrypted, equals(originalJson));
    });

    test('wrong password throws FormatException', () {
      final original = utf8.encode('Secret data');
      final encrypted = BackupCrypto.encryptBytes(original, password);

      expect(
        () => BackupCrypto.decryptBytes(encrypted, wrongPassword),
        throwsA(isA<FormatException>()),
      );
    });

    test('corrupted data throws', () {
      final original = utf8.encode('Some data');
      final encrypted = BackupCrypto.encryptBytes(original, password);

      // Corrupt the ciphertext (not salt/IV)
      encrypted[encrypted.length - 1] ^= 0xFF;

      expect(
        () => BackupCrypto.decryptBytes(encrypted, password),
        throwsA(isA<FormatException>()),
      );
    });

    test('too short data throws ArgumentError', () {
      expect(
        () => BackupCrypto.decryptBytes([1, 2, 3], password),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty data throws ArgumentError', () {
      expect(
        () => BackupCrypto.decryptBytes([], password),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('each encryption produces different output (random salt/IV)', () {
      final original = utf8.encode('Same data');
      final encrypted1 = BackupCrypto.encryptBytes(original, password);
      final encrypted2 = BackupCrypto.encryptBytes(original, password);

      // Different salt/IV should produce different ciphertext
      expect(encrypted1, isNot(equals(encrypted2)));

      // But both should decrypt to the same value
      expect(
        BackupCrypto.decryptBytes(encrypted1, password),
        equals(original),
      );
      expect(
        BackupCrypto.decryptBytes(encrypted2, password),
        equals(original),
      );
    });

    test('encrypted data is smaller than uncompressed (gzip compression)', () {
      // Highly compressible data
      final original = utf8.encode('A' * 10000);
      final encrypted = BackupCrypto.encryptBytes(original, password);

      // Overhead: 16 (salt) + 16 (IV) + AES padding, but gzip should
      // compress 10000 identical bytes significantly
      expect(encrypted.length, lessThan(original.length));
    });
  });
}
