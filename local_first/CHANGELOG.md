## 0.6.0

- BREAKING: Replace `LocalFirstModel` mixin with `LocalFirstEvent<T>` wrapper for sync metadata
- BREAKING: `DataSyncStrategy.onPushToRemote` now receives `LocalFirstEvent<T>`
- Queries now return plain models; sync metadata lives on events
- Examples and docs updated to the new event-based flow

## 0.5.0

- Split storage adapters into separate publishable packages:
  - `local_first_hive_storage` for Hive-based storage
  - `local_first_sqlite_storage` for SQLite-based storage
- Core package no longer bundles adapter implementations.
- Documentation and tooling updated for addon packages.

## 0.4.0

- Add SQLite storage adapter (`SqliteLocalFirstStorage`) with schema/index support and query filtering
- Document how to choose between Hive and SQLite storage backends
- Expand example tooling with launch configs and relational sample polish

## 0.3.0

- Switch models to the `LocalFirstModel` mixin for direct field access without wrappers
- Expand automated test suite to achieve full 100% test coverage of core flows and APIs
- Refresh README roadmap/goals to reflect documentation and testing updates

## 0.2.0

- Replace singleton `LocalFirst` with injectable `LocalFirstClient`
- Standardize storage interface as `LocalFirstStorage` with Hive implementation
- Repositories now carry serialization/conflict logic directly
- Example app updated to new client/repository APIs and string-based metadata

## 0.0.1

* Initial scaffolding
