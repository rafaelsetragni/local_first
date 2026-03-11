## 0.1.0

* Initial release
* iCloud backup provider for the LocalFirst framework
* Uses iCloud Documents for native iOS/macOS backup support
* Automatic authentication via Apple ID — no sign-in flow required
* Upload, download, list, and delete backup operations
* Configurable subfolder within the iCloud container
* Platform guard: throws `UnsupportedError` on non-Apple platforms
* Full test coverage with injectable delegate for mocking
