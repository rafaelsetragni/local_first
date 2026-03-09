# local_first_icloud_backup

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_icloud_backup.svg)](https://pub.dev/packages/local_first_icloud_backup)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

An iCloud backup provider for the [LocalFirst](https://pub.dev/packages/local_first) framework. Backup and restore your local-first data using iCloud Documents — the same approach used by WhatsApp on iOS.

> **Note:** This is a companion package to `local_first`. You need to install the core package first.

## Why local_first_icloud_backup?

- **WhatsApp-style backups**: Uses iCloud Documents, the native iOS/macOS backup mechanism
- **AES-256 encryption**: Backups are encrypted with a user-provided password before upload
- **Zero authentication**: Automatically uses the device's Apple ID — no sign-in flow needed
- **Native integration**: Uses Apple's iCloud APIs for reliable cloud storage
- **Simple API**: Upload, download, list, and delete backups with a single method call
- **Incremental restore**: Restores merge with existing data instead of overwriting

## Features

- ✅ **iCloud Documents Storage**: Native Apple cloud storage integration
- ✅ **Automatic Authentication**: Uses the device's Apple ID — no sign-in required
- ✅ **Upload/Download Backups**: Full backup lifecycle management
- ✅ **List Available Backups**: Browse and select backups to restore
- ✅ **Delete Old Backups**: Clean up iCloud storage when no longer needed
- ✅ **Configurable Subfolder**: Organize backups in custom subdirectories
- ✅ **Full Test Coverage**: Comprehensive unit tests with mocked iCloud APIs

## Platform Support

| Platform | Supported |
|----------|-----------|
| iOS      | ✅        |
| macOS    | ✅        |
| Android  | ❌        |
| Windows  | ❌        |
| Linux    | ❌        |
| Web      | ❌        |

> Throws `UnsupportedError` on non-Apple platforms.

## Installation

Add the dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.7.0
  local_first_icloud_backup: ^0.1.0
  # Choose your storage adapter
  local_first_hive_storage: ^0.2.0  # or
  local_first_sqlite_storage: ^0.3.0
```

Then install:

```bash
flutter pub get
```

## Setup

### Xcode Configuration

1. Open your project in Xcode
2. Select your target → **Signing & Capabilities**
3. Click **+ Capability** → add **iCloud**
4. Enable **iCloud Documents**
5. Add your container identifier (e.g., `iCloud.com.example.myapp`)

### Info.plist (iOS)

Ensure iCloud entitlements are properly configured. Xcode usually handles this automatically when you add the capability.

### Entitlements (macOS)

For macOS, also add the following to your `.entitlements` file:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.example.myapp</string>
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.example.myapp</string>
</array>
```

## Quick Start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_icloud_backup/local_first_icloud_backup.dart';

// 1) Create the provider (no sign-in needed!)
final icloudProvider = ICloudBackupProvider(
  containerId: 'iCloud.com.example.myapp',
  subfolder: 'my_app_backups', // optional, defaults to 'local_first_backups'
);

// 2) Create the backup service
final backupService = BackupService(client: myLocalFirstClient);

// 3) Create a backup
final metadata = await backupService.createBackup(
  provider: icloudProvider,
  password: 'user-chosen-password',
);
print('Backup created: ${metadata.fileName} (${metadata.sizeInBytes} bytes)');

// 4) List available backups
final backups = await backupService.listBackups(icloudProvider);
for (final backup in backups) {
  print('${backup.fileName} - ${backup.createdAt}');
}

// 5) Restore from a backup
await backupService.restoreBackup(
  provider: icloudProvider,
  metadata: backups.first,
  password: 'user-chosen-password',
);

// 6) Delete a backup
await backupService.deleteBackup(
  provider: icloudProvider,
  metadata: backups.last,
);
```

## How It Works

### Backup Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  LocalFirstClient│────▶│  BackupService    │────▶│  ICloudBackup    │
│                  │     │                   │     │  Provider        │
│  - repositories  │     │  1. Collect data  │     │                  │
│  - events        │     │  2. JSON encode   │     │  Write temp file │
│  - config        │     │  3. Gzip compress  │     │  Upload to iCloud│
│                  │     │  4. AES-256 encrypt│     │  Clean up temp   │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

### Restore Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  ICloudBackup    │────▶│  BackupService    │────▶│  LocalFirstClient│
│  Provider        │     │                   │     │                  │
│                  │     │  1. AES-256 decrypt│     │  Incremental     │
│  Download from   │     │  2. Gunzip         │     │  merge via       │
│  iCloud Documents│     │  3. JSON decode    │     │  pullChanges()   │
│  Clean up temp   │     │  4. Restore config │     │                  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

## Architecture

### iCloud Documents

iCloud Documents provides native Apple cloud storage:

- **Automatic sync** — Apple handles upload/download synchronization
- **Offline support** — files are cached locally and synced when online
- **Apple ID auth** — no separate sign-in needed, uses the device's Apple ID
- **Cross-device** — backups are accessible on any device with the same Apple ID

### Storage Structure

```
iCloud Container (iCloud.com.example.myapp)/
└── local_first_backups/           ← configurable via subfolder
    ├── backup_2026-03-01T12:00:00Z.lfbk
    ├── backup_2026-03-05T08:30:00Z.lfbk
    └── backup_2026-03-09T15:45:00Z.lfbk
```

## Configuration

### Container ID

The container ID must match your Xcode iCloud entitlement:

```dart
final provider = ICloudBackupProvider(
  containerId: 'iCloud.com.example.myapp', // must match Xcode config
);
```

### Custom Subfolder

Organize backups in a custom subdirectory:

```dart
final provider = ICloudBackupProvider(
  containerId: 'iCloud.com.example.myapp',
  subfolder: 'production_backups',
);
```

## Comparison with Other Providers

| Feature | iCloud | GDrive | Firebase Storage |
|---------|--------|--------|-----------------|
| Platform | iOS, macOS only | Android, iOS, Web | All platforms |
| Auth | Automatic (Apple ID) | Google Sign-In | Firebase Auth |
| Storage Location | iCloud Documents | App Data folder | Firebase Storage |
| User Visibility | Visible in iCloud | Hidden | Hidden |
| Quota Impact | Yes (iCloud quota) | No | Yes (Firebase quota) |
| Best For | Apple-only apps | Android-first apps | Cross-platform apps |

## Best Practices

1. **Match container IDs**: Ensure `containerId` matches your Xcode iCloud entitlement exactly
2. **Check platform**: The provider throws `UnsupportedError` on non-Apple platforms — guard with `Platform.isIOS || Platform.isMacOS`
3. **Limit backup count**: Delete old backups to avoid excessive iCloud storage usage
4. **Use strong passwords**: The encryption is only as strong as the user's password
5. **Test on real devices**: iCloud functionality requires a real Apple ID and device

## Troubleshooting

### UnsupportedError on Construction

- This provider only works on iOS and macOS
- Use `GDriveBackupProvider` or `FirebaseBackupProvider` for other platforms

### Upload Fails

- Verify the container ID matches your Xcode iCloud entitlement
- Check that iCloud is enabled on the device (Settings → Apple ID → iCloud)
- Ensure the device has sufficient iCloud storage

### Backups Not Appearing

- iCloud sync may take a few seconds — wait and retry
- Verify you're using the same `subfolder` for upload and list operations
- Check that the Apple ID is the same on all devices

### Entitlement Errors

- Re-add the iCloud capability in Xcode
- Clean and rebuild the project
- Verify your provisioning profile includes iCloud entitlements

## Testing

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_first_icloud_backup/local_first_icloud_backup.dart';
import 'package:mocktail/mocktail.dart';

class MockDelegate extends Mock implements ICloudStorageDelegate {}

void main() {
  test('uploads backup to iCloud', () async {
    final mockDelegate = MockDelegate();
    final provider = ICloudBackupProvider(
      containerId: 'iCloud.com.test',
      delegate: mockDelegate,
    );

    // ... set up mocks and test
  });
}
```

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs, and feel free to submit pull requests. See the main [local_first](https://pub.dev/packages/local_first) repository for guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
