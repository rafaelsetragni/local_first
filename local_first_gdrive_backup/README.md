# local_first_gdrive_backup

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_gdrive_backup.svg)](https://pub.dev/packages/local_first_gdrive_backup)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

A Google Drive backup provider for the [LocalFirst](https://pub.dev/packages/local_first) framework. Backup and restore your local-first data using Google Drive's hidden App Data folder — the same approach used by WhatsApp on Android.

> **Note:** This is a companion package to `local_first`. You need to install the core package first.

## Why local_first_gdrive_backup?

- **WhatsApp-style backups**: Uses the hidden App Data folder, invisible to the user in their Drive
- **AES-256 encryption**: Backups are encrypted with a user-provided password before upload
- **Cross-platform**: Works on Android, iOS, and web via Google Sign-In
- **Automatic authentication**: Built-in Google Sign-In with `drive.appdata` scope
- **Simple API**: Upload, download, list, and delete backups with a single method call
- **Incremental restore**: Restores merge with existing data instead of overwriting

## Features

- ✅ **Google Drive App Data Folder**: Hidden storage only your app can access
- ✅ **Google Sign-In Integration**: Built-in authentication flow
- ✅ **Upload/Download Backups**: Full backup lifecycle management
- ✅ **List Available Backups**: Browse and select backups to restore
- ✅ **Delete Old Backups**: Clean up storage when no longer needed
- ✅ **Configurable Folder Name**: Organize backups in custom subfolders
- ✅ **Full Test Coverage**: Comprehensive unit tests with mocked Google APIs

## Installation

Add the dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.7.0
  local_first_gdrive_backup: ^0.1.0
  # Choose your storage adapter
  local_first_hive_storage: ^0.2.0  # or
  local_first_sqlite_storage: ^0.3.0
```

Then install:

```bash
flutter pub get
```

## Setup

### Android

Add the following to your `android/app/build.gradle`:

```gradle
dependencies {
    implementation 'com.google.android.gms:play-services-auth:21.0.0'
}
```

Configure your OAuth 2.0 Client ID in the [Google Cloud Console](https://console.cloud.google.com/apis/credentials). Enable the **Google Drive API** and create an Android OAuth client with your app's SHA-1 fingerprint.

### iOS

Add your `GoogleService-Info.plist` to the iOS project and configure the URL scheme in `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

## Quick Start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_gdrive_backup/local_first_gdrive_backup.dart';

// 1) Create the provider
final gdriveProvider = GDriveBackupProvider(
  folderName: 'my_app_backups', // optional, defaults to 'local_first_backups'
);

// 2) Sign in with Google (required before any operation)
await gdriveProvider.signIn();

// 3) Create the backup service
final backupService = BackupService(client: myLocalFirstClient);

// 4) Create a backup
final metadata = await backupService.createBackup(
  provider: gdriveProvider,
  password: 'user-chosen-password',
);
print('Backup created: ${metadata.fileName} (${metadata.sizeInBytes} bytes)');

// 5) List available backups
final backups = await backupService.listBackups(gdriveProvider);
for (final backup in backups) {
  print('${backup.fileName} - ${backup.createdAt}');
}

// 6) Restore from a backup
await backupService.restoreBackup(
  provider: gdriveProvider,
  metadata: backups.first,
  password: 'user-chosen-password',
);

// 7) Delete a backup
await backupService.deleteBackup(
  provider: gdriveProvider,
  metadata: backups.last,
);

// 8) Sign out when done
await gdriveProvider.signOut();
```

## How It Works

### Backup Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  LocalFirstClient│────▶│  BackupService    │────▶│  GDriveBackup    │
│                  │     │                   │     │  Provider        │
│  - repositories  │     │  1. Collect data  │     │                  │
│  - events        │     │  2. JSON encode   │     │  Upload to       │
│  - config        │     │  3. Gzip compress  │     │  App Data folder │
│                  │     │  4. AES-256 encrypt│     │                  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

### Restore Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  GDriveBackup    │────▶│  BackupService    │────▶│  LocalFirstClient│
│  Provider        │     │                   │     │                  │
│                  │     │  1. AES-256 decrypt│     │  Incremental     │
│  Download from   │     │  2. Gunzip         │     │  merge via       │
│  App Data folder │     │  3. JSON decode    │     │  pullChanges()   │
│                  │     │  4. Restore config │     │                  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

## Architecture

### App Data Folder

Google Drive's App Data folder is a special hidden folder:

- **Invisible** to users — they won't see backup files in their Drive
- **App-scoped** — only your app can access its own App Data
- **Automatic cleanup** — uninstalling the app revokes access (data is retained)
- **No quota impact** — App Data doesn't count against the user's storage quota

### Storage Structure

```
Google Drive App Data/
└── local_first_backups/           ← configurable via folderName
    ├── backup_2026-03-01T12:00:00Z.lfbk
    ├── backup_2026-03-05T08:30:00Z.lfbk
    └── backup_2026-03-09T15:45:00Z.lfbk
```

## Configuration

### Custom Folder Name

Organize backups in a custom subfolder within App Data:

```dart
final provider = GDriveBackupProvider(
  folderName: 'production_backups',
);
```

### Sign-In Scopes

The provider automatically requests the `drive.appdata` scope, which only grants access to the hidden App Data folder — not the user's files.

## Comparison with Other Providers

| Feature | GDrive | iCloud | Firebase Storage |
|---------|--------|--------|-----------------|
| Platform | Android, iOS, Web | iOS, macOS only | All platforms |
| Auth | Google Sign-In | Automatic (Apple ID) | Firebase Auth |
| Storage Location | App Data folder | iCloud Documents | Firebase Storage |
| User Visibility | Hidden | Visible in iCloud | Hidden |
| Quota Impact | No | Yes (iCloud quota) | Yes (Firebase quota) |
| Best For | Android-first apps | Apple-only apps | Cross-platform apps |

## Best Practices

1. **Sign in early**: Call `signIn()` during app initialization so backups are ready when needed
2. **Handle sign-in cancellation**: `signIn()` throws `StateError` if the user cancels — show a user-friendly message
3. **Limit backup count**: Delete old backups after creating new ones to save storage
4. **Use strong passwords**: The encryption is only as strong as the user's password
5. **Test restore flow**: Always verify backups can be restored before relying on them

## Troubleshooting

### Google Sign-In Fails

- Verify your OAuth 2.0 Client ID is configured correctly
- Check that the Google Drive API is enabled in the Cloud Console
- Ensure the SHA-1 fingerprint matches your app's signing key

### Upload Returns Error

- Check that the user is signed in (`signIn()` was called successfully)
- Verify internet connectivity
- Check Google Cloud Console for API quota limits

### Backups Not Appearing in List

- Ensure you're using the same `folderName` for upload and list operations
- Verify the Google account is the same one used for upload

### Sign-In Scope Issues

- The provider only requests `drive.appdata` scope — if you need broader Drive access, handle it separately
- On iOS, ensure the URL scheme is configured in `Info.plist`

## Testing

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:local_first_gdrive_backup/local_first_gdrive_backup.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveApi extends Mock implements drive.DriveApi {}

void main() {
  test('uploads backup to App Data folder', () async {
    final mockApi = MockDriveApi();
    final provider = GDriveBackupProvider(driveApi: mockApi);

    // ... set up mocks and test
  });
}
```

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs, and feel free to submit pull requests. See the main [local_first](https://pub.dev/packages/local_first) repository for guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
