import 'package:local_first/local_first.dart';
import 'field_names.dart';

class CounterLogModel {
  final String id;
  final String username;
  final String? sessionId;
  final int increment;
  final DateTime createdAt;
  final DateTime updatedAt;

  CounterLogModel._({
    required this.id,
    required this.username,
    required this.sessionId,
    required this.increment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CounterLogModel({
    String? id,
    required String username,
    required String? sessionId,
    required int increment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    final created = createdAt ?? now;
    final updated = updatedAt ?? created;
    return CounterLogModel._(
      id: id ?? '${username}_${now.millisecondsSinceEpoch}',
      username: username,
      sessionId: sessionId,
      increment: increment,
      createdAt: created,
      updatedAt: updated,
    );
  }

  JsonMap toJson() {
    return {
      CommonFields.id: id,
      CommonFields.username: username,
      CounterLogFields.sessionId: sessionId,
      CounterLogFields.increment: increment,
      CommonFields.createdAt: createdAt.toUtc().toIso8601String(),
      CommonFields.updatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  factory CounterLogModel.fromJson(JsonMap json) {
    final created = DateTime.parse(json[CommonFields.createdAt]).toUtc();
    final updated = json[CommonFields.updatedAt] != null
        ? DateTime.parse(json[CommonFields.updatedAt]).toUtc()
        : created;
    return CounterLogModel(
      id: json[CommonFields.id],
      username: json[CommonFields.username],
      sessionId: json[CounterLogFields.sessionId],
      increment: json[CounterLogFields.increment],
      createdAt: created,
      updatedAt: updated,
    );
  }

  static CounterLogModel resolveConflict(
    CounterLogModel local,
    CounterLogModel remote,
  ) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;

  @override
  String toString() {
    final change = increment.abs();
    final verb = increment >= 0 ? 'Increased' : 'Decreased';
    return '$verb by $change by $username';
  }

  String toFormattedDate() => () {
        final local = createdAt.toLocal();
        String two(int v) => v.toString().padLeft(2, '0');
        String three(int v) => v.toString().padLeft(3, '0');
        return '${two(local.day)}/${two(local.month)}/${local.year} '
            '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.${three(local.millisecond)}';
      }();
}
