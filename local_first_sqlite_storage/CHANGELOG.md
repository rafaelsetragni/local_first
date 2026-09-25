## 0.5.0

- Implemented `LocalFirstStorage.deleteAllSynced`: drops every state row whose
  events are all synced, with those events, and returns how many rows went. A
  row with an event still waiting to be sent stays, with its events. Both
  deletes run in one transaction, joining the one in progress when there is one,
  and watchers are notified only when something was removed.
- Implemented `LocalFirstStorage.deleteWhere`: drops every state row whose
  `field` equals `value`, and the events logged for those rows, in one
  transaction. A field declared in the repository's schema is matched on its own
  indexed column; any other field is read out of the stored payload with
  `json_extract`, which scans the table — declare the fields you drop by. A
  `null` value matches the rows that do not have the field.
- Added **`SqliteLocalFirstStorage.deleteDatabases(databaseName)`**, a static
  call that removes the database file of the default namespace and of every
  other namespace (`<namespace>__<databaseName>`), with the journal files beside
  them, and returns how many were removed. For an app whose data model moved on:
  the new model opens under a new `databaseName`, and the files nothing will
  open again leave the device. Never call it with the name of an open database.
  Takes an optional `directory` (the platform's databases folder by default) and
  `dbFactory`.
- Fixed `deleteEvent`, which asked for `id = ?`: the event table has no `id`
  column, so the statement matched nothing on every database but a legacy one
  and the event stayed. It now asks by the event id.
- A watcher reads **one query at a time**. Two writes side by side notified
  twice, the two reads could finish in either order, and the watcher was left
  showing the older result. A notification that arrives while a read is running
  asks for exactly one more read, so the last emission is the newest state.
- Requires `local_first` `^0.9.0`.
- The README documents the new operations, and its installation snippet now
  names the real package versions.

## 0.4.2

- Table/schema verification (`_ensureTables`) now runs **once per repository
  per open** and concurrent first touches **share one run**. Previously every
  CRUD/query call re-ran the `PRAGMA table_info` + `CREATE INDEX` pass, and N
  concurrent calls on a table that needed a column migration all read the
  PRAGMA before any `ALTER TABLE` ran — all but the first then failed with
  `duplicate column name`, while the others queued behind the lock
  ("database has been locked for 10s"). Seen in the chat app when several
  chats loaded their history at once after a schema that added `chat_id`.
- The column migration tolerates a `duplicate column` error from a competing
  verification (e.g. one running inside a transaction, which cannot join the
  shared run without deadlocking) instead of surfacing it.
- The memo is reset by `close()` (namespace switch) and by `ensureSchema()`
  (a re-declared schema may need new columns).

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
