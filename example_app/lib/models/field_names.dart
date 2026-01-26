/// Centralized string keys to avoid magic field names.
class RepositoryNames {
  static const user = 'user';
  static const counterLog = 'counter_log';
  static const sessionCounter = 'session_counter';
}

class CommonFields {
  static const id = 'id';
  static const username = 'username';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

class UserFields {
  static const avatarUrl = 'avatar_url';
}

class CounterLogFields {
  static const sessionId = 'session_id';
  static const increment = 'increment';
}

class SessionCounterFields {
  static const sessionId = 'session_id';
  static const count = 'count';
}
