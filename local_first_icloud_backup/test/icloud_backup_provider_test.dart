import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_icloud_backup/local_first_icloud_backup.dart';

void main() {
  group('ICloudBackupProvider', () {
    test('throws UnsupportedError on non-Apple platforms', () {
      if (!Platform.isIOS && !Platform.isMacOS) {
        expect(
          () => ICloudBackupProvider(containerId: 'iCloud.com.test'),
          throwsA(isA<UnsupportedError>()),
        );
      }
    }, skip: Platform.isIOS || Platform.isMacOS ? 'Running on Apple platform' : null);

    test('can be instantiated on Apple platforms', () {
      if (Platform.isIOS || Platform.isMacOS) {
        final provider = ICloudBackupProvider(
          containerId: 'iCloud.com.test',
        );
        expect(provider.containerId, equals('iCloud.com.test'));
        expect(provider.subfolder, equals('local_first_backups'));
      }
    }, skip: !Platform.isIOS && !Platform.isMacOS ? 'Not an Apple platform' : null);

    test('accepts custom subfolder', () {
      if (Platform.isIOS || Platform.isMacOS) {
        final provider = ICloudBackupProvider(
          containerId: 'iCloud.com.test',
          subfolder: 'my_backups',
        );
        expect(provider.subfolder, equals('my_backups'));
      }
    }, skip: !Platform.isIOS && !Platform.isMacOS ? 'Not an Apple platform' : null);
  });
}
