import 'dart:io';

import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../local_first/test/src/data_sources/watch_distribution_contract.dart';

/// The contract every storage owes its watchers, over SQLite: a real file per
/// namespace, written and read off the isolate, with real transactions.
void main() {
  sqfliteFfiInit();
  late Directory folder;

  watchDistributionContract(
    'SqliteLocalFirstStorage',
    create: () async {
      folder = await Directory.systemTemp.createTemp('local_first_watch');
      await databaseFactoryFfi.setDatabasesPath(folder.path);
      return SqliteLocalFirstStorage(
        databaseName: 'watch.db',
        dbFactory: databaseFactoryFfi,
      );
    },
    destroy: (_) => folder.delete(recursive: true),
  );
}
