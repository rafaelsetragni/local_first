## 0.4.1

- Implemented `LocalFirstStorage.runInTransaction`: applies a batch inside a
  single `db.transaction`, routing all CRUD/queries through the transaction
  executor so the whole batch **commits once** (a single fsync) and **rolls back
  atomically** on error. Watcher notifications are **deferred and flushed once**
  after commit instead of re-emitting on every write.
- `getAllEvents` now accepts an optional `dataId` and pushes it down to a SQL
  `WHERE`, so callers that only need one record's history don't scan the whole
  event log.
- Together these make a large cold sync dramatically faster on slower devices
  (profiling: applying ~98 records ~8s → ~3s), by cutting per-row fsyncs and
  redundant watcher re-queries.
- Added an indexed `getById` (primary-key lookup) and `watchChanges`, a broadcast
  change signal per namespace, plus optional query profiling. Kept WAL journal
  mode after A/B profiling (WAL ~2121ms vs DELETE ~2437ms on the sync-apply
  benchmark).
- Schema-driven migration: a table created by an older app version is upgraded in
  place (`ALTER TABLE` + backfill) when its schema gains columns, instead of
  failing on the missing column.
- Reads (`getById` / `getAll` / `getAllEvents` / `getEventById`) now retry on the
  base connection when a concurrent `runInTransaction` batch commits/closes the
  shared transaction mid-read (`transaction_closed`) instead of throwing — e.g. a
  read triggered while a reconnect sync storm is applying a batch.

## 0.4.0

- Added `setPassword()` to allow changing the SQLCipher encryption password at runtime.
- Fixed `database_closed` race condition during namespace switch.
- Fixed `SqlCipherOpenDatabaseOptions` usage and improved namespace switch protection.
- Updated documentation with encryption setup and ProGuard configuration.

## 0.3.0

- Enhanced SQL query construction for better performance
- Fixed handling of lastEventId field in insert and upsert operations
- Improved query observer implementation with proper type preservation
- Fixed includeDeleted filter argument ordering in SQL queries
- Updated dependency: local_first ^0.7.0

## 0.2.0

- Add supported config types table and example app/run instructions to README.
- Link to root contributing guide; keep docs aligned with other adapters.

## 0.1.0

- Fix pubspec metadata and align workspace configuration.
- Bundle example app copy configured for the SQLite adapter.

## 0.0.1

- Initial release of the SQLite adapter for local_first.
- Supports schema/index creation, rich filtering/sorting, metadata storage, and reactive queries.
