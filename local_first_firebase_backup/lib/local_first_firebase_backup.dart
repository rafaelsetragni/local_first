/// Firebase Storage backup provider for the LocalFirst framework.
///
/// Stores encrypted backup files in Firebase Cloud Storage under the
/// authenticated user's UID path. Works on Android, iOS, web, and desktop.
///
/// ## Usage
///
/// ```dart
/// import 'package:local_first_firebase_backup/local_first_firebase_backup.dart';
///
/// final provider = FirebaseBackupProvider();
///
/// final backupService = BackupService(client: myClient);
/// final metadata = await backupService.createBackup(
///   provider: provider,
///   password: 'user-password',
/// );
/// ```
///
/// ## Setup
///
/// 1. Initialize Firebase in your app (`Firebase.initializeApp()`)
/// 2. Authenticate a user via Firebase Auth
/// 3. Configure Firebase Storage security rules to restrict access per user:
///
/// ```
/// rules_version = '2';
/// service firebase.storage {
///   match /b/{bucket}/o {
///     match /backups/{userId}/{allPaths=**} {
///       allow read, write: if request.auth != null && request.auth.uid == userId;
///     }
///   }
/// }
/// ```
library;

export 'src/firebase_backup_provider.dart';
