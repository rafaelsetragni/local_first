# Contributing to local_first

Thanks for helping make `local_first` better! We welcome pull requests for core features, storage adapters, docs, and examples. Please keep contributions aligned with the current architecture and prefer additive, backwards-compatible changes.

Key guidelines:
1. Keep storage-specific code inside its adapter package (`local_first_hive_storage`, `local_first_sqlite_storage`).
2. Add/adjust tests alongside code changes; ensure `flutter test` (and adapter tests) pass.
3. Follow [Effective Dart docs](https://dart.dev/guides/language/effective-dart/documentation) for public API comments.
4. Prefer small, focused PRs with clear rationale.

## Environment setup

This monorepo uses [Melos](https://melos.invertase.dev) to manage packages.

To install Melos, run the following command from a terminal/command prompt:

```
dart pub global activate melos
```

At the root of your locally cloned repository bootstrap the all dependencies and link them locally

```
melos bootstrap
```

This links local packages and installs dependencies across the monorepo (core, adapters, examples). No need for manual `dependency_overrides` or individual `flutter pub get`.

## Branch strategy

- `main`: ***release-only***; tracks published, stable versions. Do not open PRs against `main`.
- `development`: active work and integration branch. All feature/fix PRs must target `development`. PRs aimed at `main` will be rejected.

## Tests

- Core: `cd local_first && melos run test` (or `flutter test` within the package).
- Hive adapter: run tests in `local_first_hive_storage/test`.
- SQLite adapter: run tests in `local_first_sqlite_storage/test` (use `sqflite_common_ffi` where applicable).
- Examples: keep build/analysis clean; add minimal smoke tests where practical.

## Issues

File bugs and feature requests in this repository. Include steps to reproduce, expected vs actual behavior, and environment details (Flutter/Dart versions). PRs are appreciated for well-scoped fixes and improvements.
