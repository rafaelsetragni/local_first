# Local First monorepo

This repository hosts the local-first data layer for Flutter and its optional storage adapters.

Packages:
- `local_first`: core client, repositories, sync contracts, utilities.
- `local_first_hive_storage`: Hive adapter (schema-less boxes).
- `local_first_sqlite_storage`: SQLite adapter (structured tables with indexes).

Examples:
- `local_first/example/lib/main.dart`: Hive-based sample.
- `local_first/example/lib/main_relational.dart`: SQLite-based sample.

## Pull payload shape (server → client)

When pulling changes, the server should return a JSON object keyed by repository
name. Each entry contains the latest `server_sequence` for that repository and
the list of events to apply:

```json
{
  "users": {
    "server_sequence": 12345,
    "events": [
      {
        "event_id": "uuid-v7",
        "record_id": "u1",
        "operation": 0,
        "status": 2,
        "created_at": 1717580000000,
        "payload": { "id": "u1", "name": "Alice" }
      },
      {
        "event_id": "uuid-v7",
        "record_id": "u2",
        "operation": 2,
        "status": 2,
        "created_at": 1717580001000,
        "payload": { "id": "u2" }
      }
    ]
  },
  "posts": {
    "server_sequence": 67890,
    "events": [
      {
        "event_id": "uuid-v7",
        "record_id": "p1",
        "operation": 1,
        "status": 2,
        "created_at": 1717580002000,
        "payload": { "id": "p1", "title": "Hello" }
      }
    ]
  }
}
```

Notes:
- `operation` uses the enum ordering: insert=0, update=1, delete=2.
- `status` uses the enum ordering: pending=0, failed=1, ok=2.
- `created_at` is UTC in milliseconds since epoch.
- `event_id` must be unique for idempotence; resend of an already processed
  event should be ignored client-side based on this id.

## Usage

Add only what you need:
```yaml
dependencies:
  local_first: ^0.4.0
  local_first_hive_storage: ^1.0.0  # optional
  local_first_sqlite_storage: ^1.0.0 # optional
```

## Issues

Please open issues in this repository for bugs or feature requests. Keep discussions in GitHub so the community can help.

## Contributing

Contributions are welcome. See `CONTRIBUTING.md` for guidelines.
