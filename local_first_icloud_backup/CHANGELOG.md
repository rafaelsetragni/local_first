## 0.1.2

- Requires `local_first` `^0.10.0`. No change to this package's API.

## 0.1.1

- Requires `local_first` `^0.9.0`. No change to this package's API.
- The README's installation snippet now names the real package versions.

## 0.1.0

* Initial release
* iCloud backup provider for the LocalFirst framework
* Uses iCloud Documents for native iOS/macOS backup support
* Automatic authentication via Apple ID — no sign-in flow required
* Upload, download, list, and delete backup operations
* Configurable subfolder within the iCloud container
* Platform guard: throws `UnsupportedError` on non-Apple platforms
* Full test coverage with injectable delegate for mocking
