# local_first_firebase_backup

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_firebase_backup.svg)](https://pub.dev/packages/local_first_firebase_backup)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

A Firebase Storage backup provider for the [LocalFirst](https://pub.dev/packages/local_first) framework. Backup and restore your local-first data using Firebase Cloud Storage — a cross-platform solution that works on Android, iOS, macOS, web, and desktop.

> **Note:** This is a companion package to `local_first`. You need to install the core package first.

## Why local_first_firebase_backup?

- **Truly cross-platform**: Works on Android, iOS, macOS, web, Windows, and Linux
- **AES-256 encryption**: Backups are encrypted with a user-provided password before upload
- **Firebase Auth integration**: Uses the authenticated user's UID for per-user backup isolation
- **Scalable storage**: Leverages Firebase Cloud Storage with Google Cloud infrastructure
- **Simple API**: Upload, download, list, and delete backups with a single method call
- **Incremental restore**: Restores merge with existing data instead of overwriting

## Features

- ✅ **Firebase Cloud Storage**: Reliable, scalable cloud storage backend
- ✅ **Per-User Isolation**: Backups stored under `backups/{uid}/` for security
- ✅ **Upload/Download Backups**: Full backup lifecycle management
- ✅ **List Available Backups**: Browse and select backups to restore
- ✅ **Delete Old Backups**: Clean up storage when no longer needed
- ✅ **Configurable Subfolder**: Organize backups in custom subdirectories
- ✅ **100% Test Coverage**: Comprehensive unit tests with mocked Firebase APIs

## Platform Support

| Platform | Supported |
|----------|-----------|
| Android  | ✅        |
| iOS      | ✅        |
| macOS    | ✅        |
| Web      | ✅        |
| Windows  | ✅        |
| Linux    | ✅        |

## Installation

Add the dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.7.0
  local_first_firebase_backup: ^0.1.0
  firebase_core: ^3.0.0
  firebase_auth: ^5.0.0
  # Choose your storage adapter
  local_first_hive_storage: ^0.2.0  # or
  local_first_sqlite_storage: ^0.3.0
```

Then install:

```bash
flutter pub get
```

## Setup

### Firebase Configuration

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add your app to the project (Android, iOS, web, etc.)
3. Enable **Firebase Authentication** (any sign-in method)
4. Enable **Firebase Storage**
5. Install the FlutterFire CLI and run `flutterfire configure`

### Storage Security Rules

Configure Firebase Storage rules to allow authenticated users to access only their own backups:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /backups/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Quick Start

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_firebase_backup/local_first_firebase_backup.dart';

// 0) Initialize Firebase (once, at app startup)
await Firebase.initializeApp();

// 1) Ensure user is authenticated
await FirebaseAuth.instance.signInAnonymously(); // or any auth method

// 2) Create the provider
final firebaseProvider = FirebaseBackupProvider(
  subfolder: 'my_app_backups', // optional, defaults to 'local_first_backups'
);

// 3) Create the backup service
final backupService = BackupService(client: myLocalFirstClient);

// 4) Create a backup
final metadata = await backupService.createBackup(
  provider: firebaseProvider,
  password: 'user-chosen-password',
);
print('Backup created: ${metadata.fileName} (${metadata.sizeInBytes} bytes)');

// 5) List available backups
final backups = await backupService.listBackups(firebaseProvider);
for (final backup in backups) {
  print('${backup.fileName} - ${backup.createdAt}');
}

// 6) Restore from a backup
await backupService.restoreBackup(
  provider: firebaseProvider,
  metadata: backups.first,
  password: 'user-chosen-password',
);

// 7) Delete a backup
await backupService.deleteBackup(
  provider: firebaseProvider,
  metadata: backups.last,
);
```

## How It Works

### Backup Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  LocalFirstClient│────▶│  BackupService    │────▶│  FirebaseBackup  │
│                  │     │                   │     │  Provider        │
│  - repositories  │     │  1. Collect data  │     │                  │
│  - events        │     │  2. JSON encode   │     │  Upload to       │
│  - config        │     │  3. Gzip compress  │     │  Firebase Storage│
│                  │     │  4. AES-256 encrypt│     │  at backups/uid/ │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

### Restore Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  FirebaseBackup  │────▶│  BackupService    │────▶│  LocalFirstClient│
│  Provider        │     │                   │     │                  │
│                  │     │  1. AES-256 decrypt│     │  Incremental     │
│  Download from   │     │  2. Gunzip         │     │  merge via       │
│  Firebase Storage│     │  3. JSON decode    │     │  pullChanges()   │
│                  │     │  4. Restore config │     │                  │
└──────────────────┘     └──────────────────┘     └──────────────────┘
```

## Architecture

### Storage Structure

Backups are stored per user under Firebase Storage:

```
Firebase Storage/
└── backups/
    └── {user-uid}/
        └── local_first_backups/           ← configurable via subfolder
            ├── backup_2026-03-01T12:00:00Z.lfbk
            ├── backup_2026-03-05T08:30:00Z.lfbk
            └── backup_2026-03-09T15:45:00Z.lfbk
```

### Per-User Isolation

Each authenticated user gets their own backup directory under `backups/{uid}/`. Combined with Firebase Storage security rules, this ensures users can only access their own backups.

## Configuration

### Custom Subfolder

Organize backups in a custom subdirectory:

```dart
final provider = FirebaseBackupProvider(
  subfolder: 'production_backups',
);
```

### Custom Firebase Instances

For apps with multiple Firebase projects:

```dart
final provider = FirebaseBackupProvider(
  storage: FirebaseStorage.instanceFor(app: secondaryApp),
  auth: FirebaseAuth.instanceFor(app: secondaryApp),
);
```

## Comparison with Other Providers

| Feature | Firebase Storage | GDrive | iCloud |
|---------|-----------------|--------|--------|
| Platform | All platforms | Android, iOS, Web | iOS, macOS only |
| Auth | Firebase Auth | Google Sign-In | Automatic (Apple ID) |
| Storage Location | Firebase Storage | App Data folder | iCloud Documents |
| User Visibility | Hidden | Hidden | Visible in iCloud |
| Quota Impact | Yes (Firebase quota) | No | Yes (iCloud quota) |
| Best For | Cross-platform apps | Android-first apps | Apple-only apps |

## Best Practices

1. **Authenticate first**: The provider requires a signed-in Firebase user — call `FirebaseAuth.instance.signIn*()` before using the provider
2. **Configure security rules**: Always restrict backup access to the owning user (see Setup section)
3. **Limit backup count**: Delete old backups to control Firebase Storage costs
4. **Use strong passwords**: The encryption is only as strong as the user's password
5. **Handle auth state**: Listen for auth state changes to update the provider when the user signs out

## Troubleshooting

### StateError: "requires an authenticated user"

- Ensure the user is signed in via Firebase Auth before calling any provider method
- Check `FirebaseAuth.instance.currentUser` is not null

### Firebase Not Initialized

- Call `Firebase.initializeApp()` before using the provider
- Ensure `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) is configured

### Upload Fails with Permission Denied

- Verify Firebase Storage security rules allow the authenticated user to write
- Check that the storage rules match the path pattern `backups/{userId}/...`

### Backups Not Appearing in List

- Ensure you're using the same `subfolder` for upload and list operations
- Verify the Firebase Auth user is the same one used for upload
- Check Firebase Storage console to confirm files exist

### Large Backup Timeout

- The provider allows up to 100MB downloads by default
- For very large backups, consider splitting data across multiple files

## Testing

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:local_first_firebase_backup/local_first_firebase_backup.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseStorage extends Mock implements FirebaseStorage {}
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

void main() {
  test('uploads backup to Firebase Storage', () async {
    final mockStorage = MockFirebaseStorage();
    final mockAuth = MockFirebaseAuth();
    final provider = FirebaseBackupProvider(
      storage: mockStorage,
      auth: mockAuth,
    );

    // ... set up mocks and test
  });
}
```

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](https://github.com/rafaelsetragni/local_first/blob/main/CONTRIBUTING.md) for guidelines.


## Support the Project 💰

Your contributions help us enhance and maintain our plugins. Donations are used to procure devices and equipment for testing compatibility across platforms and versions.

[*![Donate With Stripe](https://raw.githubusercontent.com/rafaelsetragni/awesome_task_manager/master/assets/readme/stripe.png)*](https://donate.stripe.com/3cs14Yf79dQcbU4001)
[*![Donate With Buy Me A Coffee](https://raw.githubusercontent.com/rafaelsetragni/awesome_task_manager/master/assets/readme/buy-me-a-coffee.jpeg)*](https://www.buymeacoffee.com/rafaelsetragni)

## License

This project is available under the MIT License. See `LICENSE` for details.
