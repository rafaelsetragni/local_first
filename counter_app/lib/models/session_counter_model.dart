import 'package:local_first/local_first.dart';
import 'field_names.dart';

class SessionCounterModel {
  final String id;
  final String username;
  final String sessionId;
  final int count;
  final DateTime createdAt;
  final DateTime updatedAt;

  SessionCounterModel._({
    required this.id,
    required this.username,
    required this.sessionId,
    required this.count,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SessionCounterModel({
    String? id,
    required String username,
    required String sessionId,
    int count = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    final created = createdAt ?? now;
    final updated = updatedAt ?? created;
    final normalizedId = id ?? sessionId;
    return SessionCounterModel._(
      id: normalizedId,
      username: username,
      sessionId: sessionId,
      count: count,
      createdAt: created,
      updatedAt: updated,
    );
  }

  SessionCounterModel copyWith({
    String? id,
    String? username,
    String? sessionId,
    int? count,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SessionCounterModel(
      id: id ?? this.id,
      username: username ?? this.username,
      sessionId: sessionId ?? this.sessionId,
      count: count ?? this.count,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  JsonMap toJson() {
    return {
      CommonFields.id: id,
      CommonFields.username: username,
      SessionCounterFields.sessionId: sessionId,
      SessionCounterFields.count: count,
      CommonFields.createdAt: createdAt.toUtc().toIso8601String(),
      CommonFields.updatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  factory SessionCounterModel.fromJson(JsonMap json) {
    final created = DateTime.parse(json[CommonFields.createdAt]).toUtc();
    final updated = json[CommonFields.updatedAt] != null
        ? DateTime.parse(json[CommonFields.updatedAt]).toUtc()
        : created;
    final sessionId = json[SessionCounterFields.sessionId] ?? json[CommonFields.id];
    return SessionCounterModel(
      id: json[CommonFields.id] ?? sessionId,
      username: json[CommonFields.username],
      sessionId: sessionId,
      count: json[SessionCounterFields.count] ?? 0,
      createdAt: created,
      updatedAt: updated,
    );
  }

  static SessionCounterModel resolveConflict(
    SessionCounterModel local,
    SessionCounterModel remote,
  ) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}
