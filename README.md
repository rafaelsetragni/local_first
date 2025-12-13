# Local First monorepo

This repository hosts the local-first data layer for Flutter and its optional storage adapters.

Packages:
- `local_first`: core client, repositories, sync contracts, utilities.
- `local_first_hive_storage`: Hive adapter (schema-less boxes).
- `local_first_sqlite_storage`: SQLite adapter (structured tables with indexes).

Examples:
- `local_first/example/lib/main.dart`: Hive-based sample.
- `local_first/example/lib/main_relational.dart`: SQLite-based sample.

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
