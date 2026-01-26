import 'package:local_first/local_first.dart';
import 'field_names.dart';

class UserModel {
  final String id;
  final String username;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel._({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel({
    String? id,
    required String username,
    required String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    final created = createdAt ?? now;
    final updated = updatedAt ?? created;
    final normalizedId = (id ?? username).trim().toLowerCase();
    return UserModel._(
      id: normalizedId,
      username: username,
      avatarUrl: avatarUrl,
      createdAt: created,
      updatedAt: updated,
    );
  }

  JsonMap toJson() {
    return {
      CommonFields.id: id,
      CommonFields.username: username,
      UserFields.avatarUrl: avatarUrl,
      CommonFields.createdAt: createdAt.toUtc().toIso8601String(),
      CommonFields.updatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  factory UserModel.fromJson(JsonMap json) {
    final username = json[CommonFields.username] ?? json[CommonFields.id];
    final created = DateTime.parse(json[CommonFields.createdAt]).toUtc();
    final updated = json[CommonFields.updatedAt] != null
        ? DateTime.parse(json[CommonFields.updatedAt]).toUtc()
        : created;
    return UserModel(
      id: (json[CommonFields.id] ?? username).toString().trim().toLowerCase(),
      username: username,
      avatarUrl: json[UserFields.avatarUrl],
      createdAt: created,
      updatedAt: updated,
    );
  }

  static UserModel resolveConflict(UserModel local, UserModel remote) {
    // Always prefer remote if timestamps are equal
    if (local.updatedAt == remote.updatedAt) return remote;

    // Determine which version is newer based on updatedAt
    final preferred = local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
    final fallback = identical(preferred, local) ? remote : local;

    // Merge avatar: prefer non-null value
    final avatar = preferred.avatarUrl ?? fallback.avatarUrl;

    // If merged avatar equals preferred's avatar, return preferred as-is
    // This avoids creating unnecessary new objects that trigger sync
    if (avatar == preferred.avatarUrl) {
      return preferred;
    }

    // Only create new object if merge actually changed something
    return UserModel(
      id: preferred.id,
      username: preferred.username,
      avatarUrl: avatar,
      createdAt: preferred.createdAt,
      updatedAt: preferred.updatedAt,
    );
  }
}
