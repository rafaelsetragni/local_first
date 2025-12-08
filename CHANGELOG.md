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
