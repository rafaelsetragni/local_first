import 'package:local_first/local_first.dart';

/// Manages read state by tracking last read timestamps per chat
///
/// IMPORTANT: Read timestamps are stored per namespace to ensure proper isolation
/// between different users. Each user has their own set of lastReadAt values.
class ReadStateManager {
  final LocalFirstClient client;
  final String Function() getNamespace;
  final _lastReadKeyPrefix = '__last_read__';

  ReadStateManager(this.client, this.getNamespace);

  /// Builds a namespace-aware key for storing last read timestamp
  /// Format: `{namespace}__last_read__{chatId}`
  String _buildLastReadKey(String chatId) {
    final namespace = getNamespace();
    return '${namespace}_$_lastReadKeyPrefix$chatId';
  }

  /// Gets the last read timestamp for a chat in the current namespace
  Future<DateTime?> getLastReadAt(String chatId) async {
    final key = _buildLastReadKey(chatId);
    final value = await client.getConfigValue(key);
    return value != null ? DateTime.tryParse(value) : null;
  }

  /// Saves the last read timestamp for a chat in the current namespace
  Future<void> saveLastReadAt(String chatId, DateTime timestamp) async {
    final key = _buildLastReadKey(chatId);
    await client.setConfigValue(key, timestamp.toUtc().toIso8601String());
  }

  /// Marks a chat as read by setting lastReadAt to now
  Future<void> markChatAsRead(String chatId) async {
    await saveLastReadAt(chatId, DateTime.now().toUtc());
  }
}
