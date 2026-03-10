/// Google Drive backup provider for the LocalFirst framework.
///
/// Uses the Google Drive App Data folder (hidden from the user) to store
/// encrypted backup files. Requires `google_sign_in` with the
/// `drive.appdata` scope.
///
/// ## Usage
///
/// ```dart
/// import 'package:local_first_gdrive_backup/local_first_gdrive_backup.dart';
///
/// final provider = GDriveBackupProvider();
/// await provider.signIn(); // triggers Google Sign-In
///
/// final backupService = BackupService(client: myClient);
/// final metadata = await backupService.createBackup(
///   provider: provider,
///   password: 'user-password',
/// );
/// ```
///
/// ## Android Setup
///
/// 1. Configure Google Sign-In in your Firebase/Google Cloud console
/// 2. Add `google-services.json` to `android/app/`
/// 3. No additional Android permissions needed — App Data is per-app
///
/// ## iOS Setup
///
/// 1. Add your `GoogleService-Info.plist` to the Xcode project
/// 2. Add the reversed client ID as a URL scheme in `Info.plist`
library;

export 'src/gdrive_backup_provider.dart';
