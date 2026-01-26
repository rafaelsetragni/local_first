import 'package:flutter/material.dart';

/// Centralized navigation helper
class NavigatorService {
  NavigatorService._internal();
  static NavigatorService? _instance;
  factory NavigatorService() => _instance ??= NavigatorService._internal();

  final navigatorKey = GlobalKey<NavigatorState>();

  Future<T?> push<T extends Object?>(Widget page) async =>
      navigatorKey.currentState?.push<T>(MaterialPageRoute(builder: (_) => page));

  Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    Widget page, {
    TO? result,
  }) async =>
      navigatorKey.currentState?.pushReplacement<T, TO>(
        MaterialPageRoute(builder: (_) => page),
        result: result,
      );

  void pop<T extends Object?>([T? result]) =>
      navigatorKey.currentState?.pop<T>(result);

  Future<bool> maybePop<T extends Object?>([T? result]) =>
      navigatorKey.currentState?.maybePop<T>(result) ?? Future.value(false);
}
