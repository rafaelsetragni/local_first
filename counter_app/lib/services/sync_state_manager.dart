import 'package:local_first/local_first.dart';

/// Manages sync state using server sequences per repository
///
/// IMPORTANT: Sequences are stored per namespace to ensure proper isolation
/// between different users. Each user has their own set of lastSequence values.
class SyncStateManager {
  final LocalFirstClient client;
  final String Function() getNamespace;
  final _sequenceKeyPrefix = '__last_sequence__';

  SyncStateManager(this.client, this.getNamespace);

  /// Builds a namespace-aware key for storing sequence numbers
  /// Format: `{namespace}__last_sequence__{repositoryName}`
  String _buildSequenceKey(String repositoryName) {
    final namespace = getNamespace();
    return '${namespace}_$_sequenceKeyPrefix$repositoryName';
  }

  /// Gets the last synced sequence for a repository in the current namespace
  Future<int?> getLastSequence(String repositoryName) async {
    final key = _buildSequenceKey(repositoryName);
    final value = await client.getConfigValue(key);
    return value != null ? int.tryParse(value) : null;
  }

  /// Saves the last synced sequence for a repository in the current namespace
  Future<void> saveLastSequence(String repositoryName, int sequence) async {
    final key = _buildSequenceKey(repositoryName);
    await client.setConfigValue(key, sequence.toString());
  }

  /// Extracts the maximum server sequence from a list of events
  int? extractMaxSequence(List<JsonMap<dynamic>> events) {
    if (events.isEmpty) return null;

    int? maxSequence;
    for (final event in events) {
      final seq = event['serverSequence'];
      if (seq is int) {
        maxSequence = maxSequence == null ? seq : (seq > maxSequence ? seq : maxSequence);
      }
    }
    return maxSequence;
  }
}
