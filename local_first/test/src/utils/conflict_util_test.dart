import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  LocalFirstEvent<int> remote({
    required int seq,
    required DateTime createdAt,
  }) => LocalFirstEvent.createFromRemote(
    repositoryName: 'repo',
    recordId: '1',
    operation: SyncOperation.update,
    data: 1,
    createdAt: createdAt,
    eventId: 'remote-$seq-${createdAt.microsecondsSinceEpoch}',
    serverSequence: seq,
  );

  LocalFirstEvent<int> local({
    required int? seq,
    required DateTime createdAt,
  }) => seq == null
      ? LocalFirstEvent.createLocalUpdate(
          repositoryName: 'repo',
          recordId: '1',
          data: 0,
          createdAt: createdAt,
          eventId: 'local-${createdAt.microsecondsSinceEpoch}',
        )
      : LocalFirstEvent.createFromRemote(
          repositoryName: 'repo',
          recordId: '1',
          operation: SyncOperation.update,
          data: 0,
          createdAt: createdAt,
          eventId: 'local-$seq-${createdAt.microsecondsSinceEpoch}',
          serverSequence: seq,
        );

  group('ConflictUtil.lastWriteWins', () {
    test('prefers higher server sequence', () {
      final l = remote(seq: 1, createdAt: DateTime.utc(2024, 1, 1));
      final r = remote(seq: 2, createdAt: DateTime.utc(2023, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(r));
    });

    test('prefers local when local server sequence is higher', () {
      final l = remote(seq: 3, createdAt: DateTime.utc(2022, 1, 1));
      final r = remote(seq: 1, createdAt: DateTime.utc(2025, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(l));
    });

    test('prefers event with server sequence when other is null', () {
      final l = local(seq: null, createdAt: DateTime.utc(2024, 1, 1));
      final r = remote(seq: 1, createdAt: DateTime.utc(2020, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(r));
    });

    test('when only local has server sequence, keeps local', () {
      final l = remote(seq: 5, createdAt: DateTime.utc(2021, 1, 1));
      final r = local(seq: null, createdAt: DateTime.utc(2030, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(l));
    });

    test('ties server sequence by newest createdAt', () {
      final l = remote(seq: 1, createdAt: DateTime.utc(2024, 1, 1));
      final r = remote(seq: 1, createdAt: DateTime.utc(2025, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(r));
    });

    test('ties server sequence: keeps local if local is newer', () {
      final l = remote(seq: 5, createdAt: DateTime.utc(2026, 1, 1));
      final r = remote(seq: 5, createdAt: DateTime.utc(2025, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(l));
    });

    test('when both lack server sequence, uses createdAt', () {
      final l = local(seq: null, createdAt: DateTime.utc(2024, 1, 1));
      final r = local(seq: null, createdAt: DateTime.utc(2025, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(r));
    });

    test('when both lack server sequence and local is newer, keeps local', () {
      final l = local(seq: null, createdAt: DateTime.utc(2026, 1, 1));
      final r = local(seq: null, createdAt: DateTime.utc(2025, 1, 1));
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(l));
    });

    test('prefers remote on full tie', () {
      final time = DateTime.utc(2024, 1, 1);
      final l = remote(seq: 1, createdAt: time);
      final r = remote(seq: 1, createdAt: time);
      final result = ConflictUtil.lastWriteWins(l, r);
      expect(result, same(r));
    });
  });
}
