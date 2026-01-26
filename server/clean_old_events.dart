import 'package:mongo_dart/mongo_dart.dart';

/// Script to clean old events with incorrect structure
void main() async {
  print('=== Cleaning Old Events ===\n');

  final db = await Db.create('mongodb://admin:admin@localhost:27017/local_first?authSource=admin');
  await db.open();

  print('Connected to MongoDB\n');

  // Delete events that don't have 'operation' field (old structure)
  final counterLogCollection = db.collection('counter_log');

  // Find events without operation field
  final oldEvents = await counterLogCollection.find(
    where.notExists('operation')
  ).toList();

  print('Found ${oldEvents.length} events without operation field');

  if (oldEvents.isNotEmpty) {
    for (final event in oldEvents) {
      print('  - ${event['eventId']} (sequence: ${event['serverSequence']})');
    }

    print('\nDeleting old events...');
    final result = await counterLogCollection.deleteMany(
      where.notExists('operation')
    );

    print('✓ Deleted ${result['n']} events\n');
  }

  // Also reset the sequence counter for counter_log
  final sequencesCollection = db.collection('_sequences');
  await sequencesCollection.deleteOne(where.eq('_id', 'counter_log'));
  print('✓ Reset sequence counter for counter_log\n');

  await db.close();
  print('=== Done! ===');
}
