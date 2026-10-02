## Unreleased

### A watcher is one for as long as somebody listens

- `InMemoryLocalFirstStorage.watchQuery` and `watchChanges` registered their
  watcher when the stream was created and dropped it when the last listener
  left — for good. A stream listened to again after everybody left answered
  once and was never told of a write again. A watcher is now registered when
  its first listener arrives, every time, and one nobody listens to is asked
  nothing on a write.
- What a storage owes whoever watches it is written down once, as a contract
  that every storage's tests run
  (`test/src/data_sources/watch_distribution_contract.dart`): a write reaches
  every watcher of what it changed — by id, by ids, by a field, all of them,
  the bare signal — whether it was made here or applied from the server,
  however many are watching, whenever they started, and whatever the sync
  strategies are doing, a start that never returns included.

## 0.10.0

### A write of one record is one transaction, and notifies once

- `LocalFirstRepository` writes a record and the event that wrote it — an
  upsert, an update, a delete — inside `LocalFirstStorage.runInTransaction`.
  On SQLite the row and its event commit together, and whoever watches the
  repository hears of the write once instead of once per statement, so a
  watched query is read again once per write. A write made while a batch is
  already running — a sync applying a page of remote events — joins it.
- `InMemoryLocalFirstStorage.runInTransaction` batches its notifications the
  same way: what is written inside it is told once per repository, at the end,
  and a nested call joins the batch that is running. A test over the in-memory
  storage now counts the emissions the device gets.

### Reading the local store by shape

- **`LocalFirstStorage.getAllEvents` takes `pendingOnly`.** When true, only the
  events still waiting to be sent are returned, and the condition belongs in
  the query. `LocalFirstRepository.getPendingEvents()` asks with it: collecting
  what to push no longer reads the whole event history to sift it in Dart.
- **`LocalFirstRepository.delete`** reads the history of the record it removes,
  not the event log of the whole repository.
- **`LocalFirstStorage.getByIds(tableName, ids)` and
  `LocalFirstRepository.getByIds(ids)`** read several records in one question
  with the set in it, keyed by id — where a loop of `getById` asked once per
  row. Ids the device does not hold, and records it holds as deleted, are
  absent from the answer; an empty set asks nothing.
- **`LocalFirstQuery.distinctOn(field)`** keeps one row per distinct value of
  `field`: the first one in the query's order. The newest message of every
  conversation is `orderBy('created_at', descending: true).distinctOn('page_id')`
  — one question for the whole list, not one per conversation. `LocalFirstQuery`
  gains the `distinctField` property and the `copyWith` parameter of the same
  name, and `LocalFirstQuery.keepFirstPerGroup(rows, field)` is the helper for
  storages that filter in Dart. Schema-aware storages require `field` and the
  first sort field to be declared columns of the repository.
- In the in-memory storage, two rows that sort the same are now ordered by
  their id, so the row a grouped question keeps is the one the SQL storage
  keeps.

> **For custom `LocalFirstStorage` implementations:** `getByIds` is a new
> required member, and an override of `getAllEvents` must declare the new named
> parameter `bool pendingOnly = false` — a storage without them no longer
> compiles. `getByIds` answers a map keyed by id that leaves out the ids not
> held and the rows whose last event is a delete; `getAllEvents(pendingOnly:
> true)` answers only the events whose sync status is not `ok`. A storage that
> runs queries should honour `LocalFirstQuery.distinctField` as well
> (`LocalFirstQuery.keepFirstPerGroup` does it over rows already sorted). The
> built-in storages are updated: `local_first_sqlite_storage` 0.6.0 and
> `local_first_hive_storage` 0.4.0 implement the new members, and their earlier
> versions do not compile against this release. Every package of the family
> now requires `local_first` `^0.10.0`.

## 0.9.0

### Dropping local data without telling the server

Two members on `LocalFirstStorage` (and so on every repository's storage) for
the cases where the device has to let data go, while what it still owes the
server is kept:

- **`deleteAllSynced(tableName)`** drops every item whose events are all
  synced, together with those events, and returns how many items went. An item
  with a write still waiting to be sent stays, with its events. This is the
  primitive behind a full re-sync of one repository: what the device holds is
  replaced by what the server sends, and what the device wrote and has not sent
  is sent afterwards — a re-sync that used to mean losing offline writes.
- **`deleteWhere(tableName, field:, value:)`** drops every item whose `field`
  equals `value`, with their events, and returns how many went. It is a local
  drop, not a delete to be synced: nothing is queued for the remote. It is for
  data that stopped being the device's to hold — the rows of a conversation the
  account left, of a page it unfollowed — where the server already knows and
  only the local copy has to go. A field declared in the repository's schema is
  matched on its own column; any other field is matched inside the stored
  payload.

### A delete that needs sync is sent

`_markAllPreviousEventAsOk` recognized the incoming event by its moment, and a
stored moment is kept in milliseconds: the event read back from storage was a
few microseconds behind the one in hand, so it counted as *previous* and was
marked `ok` — the write it carried was never sent. A removal made offline
vanished silently. The event is now recognized by its id, and is never one of
its own previous events.

### Watched queries — `InMemoryLocalFirstStorage`

- A watcher reads **one query at a time**. Two writes side by side notified
  twice, the two reads could finish in either order, and the watcher was left
  showing the older result. A notification that arrives while a read is running
  asks for exactly one more read, so the last emission is the newest state.
- A read iterates a snapshot of the table, so a row deleted while the read is
  in progress no longer breaks it with a concurrent-modification error — which
  is exactly what `deleteWhere` does to a watcher of the rows it removes.
- **Watchers belong to the storage, not to a namespace.** A watcher registered
  before `useNamespace` was kept in the old namespace's bucket and went silent
  after the switch; it now follows the data of whichever namespace is current
  and is re-emitted on every switch. This is
  the contract `SqliteLocalFirstStorage` already kept, so a test written over
  the in-memory storage now proves the behaviour the device gets.

> ⚠️ **For custom `LocalFirstStorage` implementations:** `deleteAllSynced` and
> `deleteWhere` are new required members — a storage that does not implement
> them no longer compiles. A backend with no way to ask for unsynced events can
> return `0` and do nothing, as long as callers are not offered a re-sync. The
> built-in Hive, SQLite and in-memory backends are already updated.

## 0.8.2

### Performance — large remote-event batches (cold sync) are now ~O(n)

Applying a large batch of remote events (typically a device's first sync) used
to be O(n²) and dominated sync time. In profiling, applying ~98 records dropped
from **~70s to ~3s**.

- `_markAllPreviousEventAsOk` now **skips events already marked `ok`** instead of
  re-writing every earlier same-record event on every incoming event (the main
  O(n²) source).
- `mergeRemoteEvent` reads each record's event history **once** and reuses it for
  both the pending-conflict check and the mark-previous pass (previously two
  identical queries per event).
- `LocalFirstStorage.getAllEvents` gained an optional **`dataId`** so callers can
  read a single record's history instead of the whole event log; the SQLite
  backend pushes it down to a SQL `WHERE`, the in-memory backend filters in Dart.
- Added **`LocalFirstStorage.runInTransaction(action)`**. `LocalFirstClient.pullChanges`
  now applies a whole batch inside one storage transaction, so backends that
  support it (SQLite) commit once and defer watcher notifications until after the
  commit.

### Read performance

- Added **`LocalFirstStorage.watchChanges(repositoryName)`** and
  `LocalFirstRepository.watchChanges()` — a lightweight change signal that emits
  on any write to a repository (plus one initial tick on listen), so callers
  reload through their own read path instead of receiving rows through the
  stream.
- Added an indexed single-item read path (`getById`) so a lookup by id uses the
  storage's primary-key index instead of scanning and deserializing the whole
  table.

> ⚠️ **For custom `LocalFirstStorage` implementations:** add `runInTransaction`
> (backends without a real transaction may just run the action), the optional
> `dataId` parameter on `getAllEvents`, and **`watchChanges`** (a broadcast
> `Stream<void>` that ticks on writes). The built-in Hive/SQLite/in-memory
> backends are already updated.

## 0.8.1

- Fixed analyzer warning in `BackupService` (unused local variable).

## 0.8.0

- Added backup & restore system with `BackupService`, `BackupData`, `BackupStorageProvider` interface, and AES-256 + gzip encryption pipeline.
- Added `local_first_firebase_backup`, `local_first_gdrive_backup`, and `local_first_icloud_backup` companion packages.
- Added configurable logger system (`LocalFirstLogger`) for all plugins with adjustable log levels.
- Added repository filtering to sync strategies via `onBuildSyncFilter` callback.
- Fixed `DateTime` serialization to ISO 8601 string in `LocalFirstEvent.toJson()`.
- Fixed orphaned events being deserialized in `getAllEvents`, preventing runtime errors.
- Fixed server event field name alignment with client convention.

### ⚠️ Breaking change — event metadata field rename

All internal event metadata keys now use a `_` prefix to prevent collision with your entity fields (e.g. a `user.created_at` field no longer conflicts with the event's own `_created_at`).

If you store or transmit raw event maps (e.g. via a custom sync backend or direct storage queries), update your field references:

| Before | After |
|---|---|
| `eventId` | `_event_id` |
| `repository` | `_repository` |
| `operation` | `_operation` |
| `createdAt` | `_created_at` |
| `data` | `_data` |
| `dataId` | `_data_id` |
| `syncStatus` | `_sync_status` |
| `lastEventId` | `_last_event_id` |

The Dart constants (`LocalFirstEvent.kEventId`, `kSyncCreatedAt`, etc.) remain unchanged — only the string values they hold have changed. If you access event fields exclusively through these constants, no code changes are needed. A one-time database migration may be required if you have existing persisted events.

## 0.7.2

- Updated README with absolute GitHub URLs for proper rendering on pub.dev
- Added sync strategy packages to Installation section (periodic and websocket)
- Reorganized Running examples section with storage adapters and sync strategies categories
- Updated package versions in Installation documentation

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
