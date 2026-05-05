## 0.2.1

- Sync cycle log lines now include the repository name and the change count, so multi-module syncs are easier to read in the device log (e.g. `Sync cycle completed for [users] (3 changes)` / `(no changes)`).
- Cleaned up analyzer warnings in `PeriodicSyncStrategy`.

## 0.2.0

- Added `forceSync()` method to trigger an immediate sync cycle outside the periodic timer.
- Added configurable logger system via `LocalFirstLogger` with adjustable log levels.
- Added repository filtering support via `onBuildSyncFilter` callback.
- Fixed event field name alignment with server convention.
- Improved test coverage.

## 0.1.0

* Initial release
* Periodic synchronization strategy for LocalFirst framework
* Configurable sync intervals
* Automatic background synchronization
* Full test coverage with 11 passing tests
* Comprehensive API documentation with usage examples
* Detailed documentation for all public methods and callbacks
