part of '../../local_first.dart';

/// Utility helpers for JSON structural equality.
sealed class JsonUtil {
  /// Returns true when two JSON-serializable structures are equal by value.
  ///
  /// Supports nested maps/lists; falls back to `==` for primitives.
  static bool equals(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return left == right;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key)) return false;
        if (!equals(entry.value, right[entry.key])) return false;
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!equals(left[i], right[i])) return false;
      }
      return true;
    }
    return left == right;
  }
}
