## 0.4.0

- Requires `local_first` `^0.10.0`, and implements what it added to the storage
  interface:
  - `getByIds(tableName, ids)` answers the records of a set of ids, keyed by id;
    the ids the box does not hold, and the records held as deleted, are left
    out. Hive has no query to send the set in, so it is one pass over the ids
    asked for.
  - `getAllEvents(pendingOnly: true)` answers only the events still waiting to
    be sent. The event box is still read through; what the filter saves is the
    merge of every synced event with its data.
  - `LocalFirstQuery.distinctOn(field)` keeps the first row of each group once
    the rows are sorted. Two rows that sort the same are now ordered by their
    id, as the SQLite storage orders them, so both keep the same row.
- `runInTransaction` still runs the action directly: Hive has no transaction,
  so the notifications of a write of one record are not batched here.
- The README's installation snippet names the new versions.

## 0.3.0

- Implemented `LocalFirstStorage.deleteAllSynced`: drops every record whose
  events are all synced, with those events, and returns how many records went. A
  record with an event still waiting to be sent stays, with its events.
- Implemented `LocalFirstStorage.deleteWhere`: drops every record whose `field`
  equals `value`, and their events, and returns how many records went. Hive has
  no index to ask, so the box is read through once — a large box pays for it.
- Requires `local_first` `^0.9.0`.
- The README documents the new operations, and its installation snippet now
  names the real package versions.

## 0.2.3

- `getAllEvents` now accepts an optional `dataId` filter, matching the updated
  `LocalFirstStorage` interface (used by the sync path to read a single record's
  history instead of the whole event log).
- Added `runInTransaction`, which runs the action directly — Hive has no
  multi-box transaction, so there is no commit-batching win here (the SQLite
  backend is the one that benefits); the method exists to satisfy the interface.
- Added `watchChanges`, backed by Hive's native `box.watch()` on the data and
  event boxes (plus one initial tick on listen), implementing the new
  `LocalFirstStorage` change-signal method.

## 0.2.2

- Removed unused import in `HiveLocalStorage` to silence the analyzer.

## 0.2.1

- Updated documentation: standardized Contributing and Support the Project sections.

## 0.2.0

- Add supported config types table and example app/run instructions to README.
- Link to root contributing guide; align docs with other adapters.

## 0.1.0

- Fix pubspec metadata and align workspace configuration.
- Bundle example app copy configured for the Hive adapter.

## 0.0.1

- Initial release of the Hive adapter for local_first.
- Provides schema-less storage via Hive, namespaces, reactive queries, and metadata support.
