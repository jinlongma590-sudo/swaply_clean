import 'package:flutter/material.dart';
import 'root_nav.dart';

class SafeNavigator {
  static Future<T?> pushNamed<T extends Object?>(
      String route, {Object? args}
      ) async {
    await Future.delayed(Duration.zero);
    final nav = rootNavKey.currentState;
    if (nav == null) return null;
    return nav.pushNamed<T>(route, arguments: args);
  }

  static Future<T?> pushNamedAndRemoveUntil<T extends Object?>(
      String route,
      bool Function(Route<dynamic>) predicate, {Object? args}
      ) async {
    await Future.microtask(() {});
    final nav = rootNavKey.currentState;
    if (nav == null) return null;
    return nav.pushNamedAndRemoveUntil<T>(route, predicate, arguments: args);
  }

  /// 支持直接 push(Route) —— 你项目里大量使用 MaterialPageRoute，需要这个
  static Future<T?> push<T extends Object?>(Route<T> route) async {
    await Future.microtask(() {});
    final nav = rootNavKey.currentState;
    if (nav == null) return null;
    return nav.push<T>(route);
  }

  static void pop<T extends Object?>([T? result]) {
    final nav = rootNavKey.currentState;
    if (nav?.canPop() ?? false) {
      nav!.pop<T>(result);
    }
  }

  static Future<bool> maybePop<T extends Object?>([T? result]) async {
    final nav = rootNavKey.currentState;
    if (nav == null) return false;
    return nav.maybePop<T>(result);
  }

  /// 服务层/深链层弹窗需要的上下文
  static BuildContext? get context => rootNavKey.currentContext;
}
