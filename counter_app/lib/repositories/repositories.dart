import 'package:local_first/local_first.dart';
import '../models/field_names.dart';
import '../models/user_model.dart';
import '../models/counter_log_model.dart';
import '../models/session_counter_model.dart';

LocalFirstRepository<UserModel> buildUserRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.user,
    getId: (user) => user.id,
    toJson: (user) => user.toJson(),
    fromJson: (json) => UserModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = UserModel.resolveConflict(local.data, remote.data);
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}

LocalFirstRepository<CounterLogModel> buildCounterLogRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.counterLog,
    getId: (log) => log.id,
    toJson: (log) => log.toJson(),
    fromJson: (json) => CounterLogModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = CounterLogModel.resolveConflict(local.data, remote.data);
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}

LocalFirstRepository<SessionCounterModel> buildSessionCounterRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.sessionCounter,
    getId: (session) => session.id,
    toJson: (session) => session.toJson(),
    fromJson: (json) => SessionCounterModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = SessionCounterModel.resolveConflict(
        local.data,
        remote.data,
      );
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}
