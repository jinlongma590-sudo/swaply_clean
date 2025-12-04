// lib/router/root_nav.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 全局根导航 Key（MaterialApp.navigatorKey 必须绑定它）
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

/// 获取全局可用的 BuildContext（谨慎使用）
BuildContext? get rootContext => rootNavKey.currentContext;

/// ====== 证据收集（仅 Debug 生效）======

String _trimStack(String full) {
  // 取前若干条“落在你项目里的”堆栈；若没有命中，就退化取前 6 条。
  final lines = full.split('\n');
  final buf = StringBuffer();
  int kept = 0;
  for (final l in lines) {
    if (l.contains('package:swaply/') || l.contains('lib/')) {
      buf.writeln(l);
      if (++kept >= 6) break;
    }
  }
  if (kept == 0) {
    for (var i = 0; i < lines.length && i < 6; i++) {
      buf.writeln(lines[i]);
    }
  }
  return buf.toString().trimRight();
}

void _evidenceNav(String api, String routeName) {
  if (!kDebugMode) return;
  if (routeName == '/welcome' || routeName == '/home') {
    final t = DateTime.now().toIso8601String();
    final st = _trimStack(StackTrace.current.toString());
    debugPrint('[EVIDENCE][$api] → $routeName  t=$t\n$st');
  }
}

/// 命名路由 push
Future<T?> navPush<T extends Object?>(
    String routeName, {
      Object? arguments,
    }) async {
  _evidenceNav('navPush', routeName); // 🔍 证据点

  final nav = rootNavKey.currentState;
  if (nav == null) return null;
  // 避免与当前帧动画/首帧竞争
  await Future<void>.delayed(Duration.zero);
  return nav.pushNamed<T>(routeName, arguments: arguments);
}

/// 命名路由：清栈并跳转
Future<T?> navReplaceAll<T extends Object?>(
    String routeName, {
      Object? arguments,
    }) async {
  _evidenceNav('navReplaceAll', routeName); // 🔍 证据点（最关键）

  final nav = rootNavKey.currentState;
  if (nav == null) return null;
  await Future<void>.delayed(Duration.zero);
  return nav.pushNamedAndRemoveUntil<T>(
    routeName,
        (route) => false,
    arguments: arguments,
  );
}

/// 直接 push 一个 Route（比如 MaterialPageRoute）
Future<T?> navPushRoute<T extends Object?>(
    Route<T> route,
    ) async {
  // 尝试从 route.settings.name 抓名字用于证据打印
  final name = route.settings.name ?? route.hashCode.toString();
  _evidenceNav('navPushRoute', name); // 🔍 证据点

  final nav = rootNavKey.currentState;
  if (nav == null) return null;
  await Future<void>.delayed(Duration.zero);
  return nav.push<T>(route);
}

/// 尝试返回上一页
Future<bool> navMaybePop<T extends Object?>([T? result]) async {
  final nav = rootNavKey.currentState;
  if (nav == null) return false;
  return nav.maybePop<T>(result);
}

/// 强制返回
void navPop<T extends Object?>([T? result]) {
  final nav = rootNavKey.currentState;
  if (nav?.canPop() ?? false) {
    nav!.pop<T>(result);
  }
}
