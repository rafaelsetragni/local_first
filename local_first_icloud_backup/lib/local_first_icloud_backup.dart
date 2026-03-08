/// iCloud backup provider for the LocalFirst framework.
///
/// Stores encrypted backup files in the iCloud Documents container.
/// Available on iOS and macOS only.
///
/// ## Usage
///
/// ```dart
/// import 'package:local_first_icloud_backup/local_first_icloud_backup.dart';
///
/// final provider = ICloudBackupProvider(
///   containerId: 'iCloud.com.example.myapp',
/// );
///
/// final backupService = BackupService(client: myClient);
/// final metadata = await backupService.createBackup(
///   provider: provider,
///   password: 'user-password',
/// );
/// ```
///
/// ## iOS/macOS Setup
///
/// 1. Enable iCloud capability in Xcode
/// 2. Enable "iCloud Documents" in the capability
/// 3. Add your iCloud container identifier
/// 4. Ensure `iCloud.com.example.myapp` matches your container ID
library;

export 'src/icloud_backup_provider.dart';
