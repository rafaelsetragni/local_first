part of '../../local_first.dart';

/// Callback signature for logging in the LocalFirst framework.
///
/// [message] - The log message to be logged
/// [name] - An optional tag/name for filtering logs (e.g., class name or feature area)
/// [error] - Optional error object associated with the log
/// [stackTrace] - Optional stack trace for error context
typedef LocalFirstLogCallback = void Function(
  String message, {
  String? name,
  Object? error,
  StackTrace? stackTrace,
});

/// Global configurable logger for the LocalFirst framework and all its plugins.
///
/// This class allows external configuration of logging behavior, enabling
/// integration with custom logging systems like LogUtil in the main app.
///
/// By default, logs are sent to `dart:developer.log`. To customize:
///
/// ```dart
/// LocalFirstLogger.configure(
///   (message, {name, error, stackTrace}) {
///     LogUtil.debug(message, name: name ?? 'LocalFirst');
///   },
/// );
/// ```
///
/// This configuration applies to all LocalFirst plugins:
/// - local_first (core)
/// - local_first_periodic_strategy
/// - local_first_websocket
/// - local_first_sqlite_storage
/// - local_first_hive_storage
/// - etc.
class LocalFirstLogger {
  /// The callback used for logging. Defaults to dart:developer.log.
  static LocalFirstLogCallback? _logCallback;

  /// Configures the logger with a custom callback.
  ///
  /// [callback] - A function that handles log messages. Set to null to reset
  /// to the default dart:developer.log behavior.
  ///
  /// Example:
  /// ```dart
  /// LocalFirstLogger.configure(
  ///   (message, {name, error, stackTrace}) {
  ///     LogUtil.debug(message, name: name ?? 'LocalFirst');
  ///   },
  /// );
  /// ```
  static void configure(LocalFirstLogCallback? callback) {
    _logCallback = callback;
  }

  /// Logs a message using the configured callback or dart:developer.log.
  ///
  /// [message] - The log message to be logged
  /// [name] - An optional tag/name for filtering logs (defaults to 'LocalFirst')
  /// [error] - Optional error object associated with the log
  /// [stackTrace] - Optional stack trace for error context
  static void log(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final callback = _logCallback;
    if (callback != null) {
      // Use configured callback
      callback(message, name: name, error: error, stackTrace: stackTrace);
    } else {
      // Fall back to dart:developer.log
      dev.log(
        message,
        name: name ?? 'LocalFirst',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
