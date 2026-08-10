## 0.2.3

- `getAllEvents` now accepts an optional `dataId` filter, matching the updated
  `LocalFirstStorage` interface (used by the sync path to read a single record's
  history instead of the whole event log).
- Added `runInTransaction`, which runs the action directly — Hive has no
  multi-box transaction, so there is no commit-batching win here (the SQLite
  backend is the one that benefits); the method exists to satisfy the interface.

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
