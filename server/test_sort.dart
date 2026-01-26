import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  final db = await Db.create('mongodb://admin:admin@127.0.0.1:27017/remote_counter_db?authSource=admin');
  await db.open();
  
  final collection = db.collection('counter_log');
  
  print('Test 1: No sort');
  var selector = where;
  var cursor = collection.find(selector);
  var results = await cursor.toList();
  print('First 3 sequences: ${results.take(3).map((e) => e['serverSequence']).toList()}');
  
  print('\nTest 2: Sort ascending');
  selector = where.sortBy('serverSequence', descending: false);
  cursor = collection.find(selector);
  results = await cursor.toList();
  print('First 3 sequences: ${results.take(3).map((e) => e['serverSequence']).toList()}');
  
  print('\nTest 3: Sort descending');
  selector = where.sortBy('serverSequence', descending: true);
  cursor = collection.find(selector);
  results = await cursor.toList();
  print('First 3 sequences: ${results.take(3).map((e) => e['serverSequence']).toList()}');
  
  await db.close();
}
