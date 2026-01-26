import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Test script to verify Hive is saving and reading values correctly
void main() async {
  print('=== Testing Hive Save/Load ===\n');

  // Initialize Hive
  final dir = await getApplicationDocumentsDirectory();
  final hivePath = '${dir.path}/test_hive';
  print('Hive path: $hivePath');

  // Clean up old test data
  final testDir = Directory(hivePath);
  if (await testDir.exists()) {
    await testDir.delete(recursive: true);
  }
  await testDir.create(recursive: true);

  Hive.init(hivePath);

  // Open config box
  final configBox = await Hive.openBox('config');
  print('✓ Opened config box\n');

  // Test 1: Save and read a sequence
  print('Test 1: Save and read sequence');
  final key = 'test_user___last_sequence__counter_log';
  print('  Key: $key');

  // Save value
  await configBox.put(key, '25');
  print('  ✓ Saved: 25');

  // Read back immediately
  final value1 = configBox.get(key);
  print('  ✓ Read back: $value1');

  if (value1 == '25') {
    print('  ✓ Test 1 PASSED\n');
  } else {
    print('  ✗ Test 1 FAILED: Expected "25", got "$value1"\n');
    exit(1);
  }

  // Test 2: Update sequence and verify
  print('Test 2: Update sequence');
  await configBox.put(key, '31');
  print('  ✓ Updated to: 31');

  final value2 = configBox.get(key);
  print('  ✓ Read back: $value2');

  if (value2 == '31') {
    print('  ✓ Test 2 PASSED\n');
  } else {
    print('  ✗ Test 2 FAILED: Expected "31", got "$value2"\n');
    exit(1);
  }

  // Test 3: Close and reopen box
  print('Test 3: Persist across box close/reopen');
  await configBox.close();
  print('  ✓ Closed box');

  final configBox2 = await Hive.openBox('config');
  print('  ✓ Reopened box');

  final value3 = configBox2.get(key);
  print('  ✓ Read back: $value3');

  if (value3 == '31') {
    print('  ✓ Test 3 PASSED\n');
  } else {
    print('  ✗ Test 3 FAILED: Expected "31", got "$value3"\n');
    exit(1);
  }

  // Test 4: Multiple keys
  print('Test 4: Multiple repository keys');
  await configBox2.put('test_user___last_sequence__user', '23');
  await configBox2.put('test_user___last_sequence__session_counter', '52');
  print('  ✓ Saved multiple keys');

  final allKeys = configBox2.keys.where((k) => k.toString().contains('__last_sequence__')).toList();
  print('  Found ${allKeys.length} sequence keys:');
  for (final k in allKeys) {
    final v = configBox2.get(k);
    print('    $k = $v');
  }

  if (allKeys.length == 3) {
    print('  ✓ Test 4 PASSED\n');
  } else {
    print('  ✗ Test 4 FAILED: Expected 3 keys, got ${allKeys.length}\n');
    exit(1);
  }

  await configBox2.close();

  print('=== ✅ All Tests Passed! ===');
  print('Hive is working correctly. The problem must be in the app logic.');

  // Clean up
  await testDir.delete(recursive: true);
}
