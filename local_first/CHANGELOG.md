## 0.7.1

- Added chat app example with real-time messaging using dual sync strategy (WebSocket + Periodic)
- Enhanced documentation with data flow diagram and fixed pub.dev package links
- Improved code examples in README with corrected syntax and API usage
- Tuned counter app sync intervals for better performance (60s heartbeat, 30s periodic)

## 0.7.0

- Added comprehensive counter app example demonstrating real-time WebSocket synchronization
- Improved test coverage and reliability across the framework
- Enhanced documentation and code examples

## 0.6.0

- Added `local_first_shared_preferences` adapter with namespaced config storage and example app.
- Unified example apps across adapters and defaulted core example to in-memory storage.
- Expanded documentation with supported config types tables, example run instructions, and contribution links.
- Refined config storage APIs (optional delegate, namespace propagation) and achieved full test coverage.
- Simplified remote pull API to make per-repository backend integrations easier.

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
