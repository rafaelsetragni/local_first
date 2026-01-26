import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  
  final dbPath = '/Users/rafaelsetragni/Library/Developer/CoreSimulator/Devices/90EC9EA7-99CA-4AF7-B3B1-93C46B0CA19E/data/Containers/Data/Application/C10E9664-0D2A-4D68-9659-C151FBE7343B/Documents/websocket_example.db';
  
  print('Opening database: $dbPath');
  final db = await databaseFactoryFfi.openDatabase(dbPath);
  
  print('\n=== Listing all tables ===');
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
  );
  print('Tables found: ${tables.length}');
  for (final table in tables) {
    print('  - ${table['name']}');
  }
  
  await db.close();
}
