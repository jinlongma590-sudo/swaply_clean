// lib/services/auth_flow_observer.dart
// ✅ [竞态修复] 防止 signedIn 和 initialSession 同时触发导致重复导航
// ✅ [方案四] 等待 Profile 加载完成再导航

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/oauth_entry.dart';
import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/services/deep_link_service.dart';
import 'package:swaply/services/deep_link_navigation_guard.dart';
import 'package:swaply/auth/register_screen.dart';

final _appStart = DateTime.now();

class AuthFlowObserver {
  AuthFlowObserver._();
  static final AuthFlowObserver I = AuthFlowObserver._();

  StreamSubscription<AuthState>? _sub;
  bool _started = false;

  bool _navigating = false;
  String? _lastEvent;
  String? _lastRoute;
  DateTime? _lastAt;
  bool _manualSignOutOnce = false;
  DateTime? _manualSignOutAt;
  Timer? _signOutDebounce;
  String? _lastUserId;
  bool _bootWatchdogArmed = false;
  bool _everNavigated = false;

  final _guard = DeepLinkNavigationGuard();

  static bool _initialNavigationDone = false;
  static bool get hasCompletedInitialNavigation => _initialNavigationDone;

  void markManualSignOut() {
    _manualSignOutOnce = true;
    _manualSignOutAt = DateTime.now();
    debugPrint('[AuthFlowObserver] markManualSignOut=true');
  }

  void clearManualSignOutFlag() {
    _manualSignOutOnce = false;
    _manualSignOutAt = null;
    debugPrint('[AuthFlowObserver] clearManualSignOutFlag called');
  }

  bool _throttle(String route, {int ms = 900}) {
    final now = DateTime.now();
    if (_lastRoute == route &&
        _lastAt != null &&
        now.difference(_lastAt!) < Duration(milliseconds: ms)) {
      return true;
    }
    return false;
  }

  String? _getCurrentRoute() {
    try {
      final navigator = rootNavKey.currentState;
      if (navigator == null) {
        if (kDebugMode) {
          debugPrint(
              '[AuthFlowObserver] _getCurrentRoute: navigator is null, returning cached: $_lastRoute');
        }
        return _lastRoute;
      }

      final context = navigator.context;
      if (context.mounted) {
        final route = ModalRoute.of(context);
        if (route != null && route.settings.name != null) {
          final routeName = route.settings.name!;
          if (kDebugMode) {
            debugPrint('[AuthFlowObserver] _getCurrentRoute: $routeName');
          }
          return routeName;
        }
      }

      if (navigator.context.mounted && _lastRoute == null) {
        if (kDebugMode) {
          debugPrint(
              '[AuthFlowObserver] _getCurrentRoute: likely on initialRoute, returning "/"');
        }
        return '/';
      }

      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] _getCurrentRoute: returning cached: $_lastRoute');
      }
      return _lastRoute;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] _getCurrentRoute error: $e');
      }
      return _lastRoute;
    }
  }

  Future<String?> _getCurrentRouteWithRetry(
      {int maxRetries = 5, int delayMs = 100}) async {
    for (int i = 0; i < maxRetries; i++) {
      final route = _getCurrentRoute();

      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] 🔍 Route check attempt ${i + 1}/$maxRetries: $route');
      }

      if (route != null &&
          route != '/' &&
          route != '/welcome' &&
          route != '/home') {
        if (kDebugMode) {
          debugPrint('[AuthFlowObserver] ✅ Found business route: $route');
        }
        return route;
      }

      if (i < maxRetries - 1) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    final finalRoute = _getCurrentRoute();
    if (kDebugMode) {
      debugPrint(
          '[AuthFlowObserver] 📍 Final route after $maxRetries attempts: $finalRoute');
    }
    return finalRoute;
  }

  Future<void> _goOnce(String route, {bool force = false}) async {
    // ✅ [竞态修复] 在最开始就设置标志，防止并发调用
    if (!_everNavigated) {
      _everNavigated = true;
      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] 🏁 First navigation initiated to: $route');
      }
    }

    if (_navigating) {
      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] ⏭️ Navigation already in progress, skipping');
      }
      return;
    }

    if (_throttle(route)) {
      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] ⏭️ Throttled navigation to $route (too soon)');
      }
      return;
    }

    if (_guard.shouldBlockNavigation(route)) {
      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] 🚫 Navigation to $route blocked by Guard');
        debugPrint('[AuthFlowObserver] 📊 Guard status: ${_guard.getStatus()}');
      }
      return;
    }

    final currentRoute = _getCurrentRoute();
    if (currentRoute == route && !force) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ⏭️ Already on $route, skip navigation');
        debugPrint(
            '[AuthFlowObserver] 📌 Preserving scroll position and page state');
      }
      _initialNavigationDone = true;
      return;
    }

    // ✅ [ProfilePage修复] 强制导航时打印说明
    if (currentRoute == route && force) {
      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] 🔄 Force navigation to $route (rebuilding page tree)');
        debugPrint(
            '[AuthFlowObserver] 💡 Reason: OAuth login requires fresh widget tree');
      }
    }

    _navigating = true;
    if (kDebugMode) {
      debugPrint('[AuthFlowObserver] 🔄 NAV -> $route (from: $currentRoute)');
    }

    var waited = 0;
    while (rootNavKey.currentState == null && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 50));
      waited += 50;
      if (kDebugMode && waited % 500 == 0) {
        debugPrint(
            '[AuthFlowObserver] ⏳ Waiting for navigation ready... (${waited}ms)');
      }
    }

    if (rootNavKey.currentState == null) {
      if (kDebugMode) {
        debugPrint(
            '[AuthFlowObserver] ❌ Navigation timeout! rootNavKey.currentState is null');
      }
      _navigating = false;
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '[AuthFlowObserver] ✅ Navigation ready (waited ${waited}ms), executing navReplaceAll');
    }

    try {
      navReplaceAll(route);
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ✅ navReplaceAll($route) executed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ❌ navReplaceAll error: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 120));

    _lastRoute = route;
    _lastAt = DateTime.now();
    _navigating = false;
    _initialNavigationDone = true;
  }

  // ✅ [方案四] 改为 async 并等待加载完成
  Future<void> _preheatProfile(User user) async {
    _lastUserId = user.id;

    if (kDebugMode) {
      debugPrint('[AuthFlowObserver] Preheating profile...');
    }

    try {
      // ✅ 等待 Profile 加载完成（会自动推送到 Stream）
      await ProfileService.i.getMyProfile().timeout(
        Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[AuthFlowObserver] ⚠️ Profile preheat timeout');
          }
          return null;
        },
      );

      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ✅ Profile preheated and stream updated');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ⚠️ Profile preheat failed: $e');
      }
      // 即使失败也继续，不阻塞导航
    }
  }

  void _armBootWatchdogOnce() {
    if (_bootWatchdogArmed) return;
    _bootWatchdogArmed = true;
    if (kDebugMode) {
      debugPrint('[AuthFlowObserver] BOOT-WATCHDOG disabled (no-op)');
    }
  }

  void start() {
    if (_started) return;
    _started = true;

    _armBootWatchdogOnce();

    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final sinceStart = DateTime.now().difference(_appStart);

      final isGraceWindowSignOut =
          sinceStart < const Duration(milliseconds: 1200) &&
              data.event == AuthChangeEvent.signedOut;

      if (isGraceWindowSignOut) {
        debugPrint(
            '[AuthFlowObserver] grace-window signedOut detected (will skip navigation but allow cleanup)');
      }

      final eventName = data.event.name;

      // ✅ [竞态修复] 增强事件过滤
      if (_lastEvent == 'signedIn' && eventName == 'initialSession') {
        if (kDebugMode) {
          debugPrint(
              '[AuthFlowObserver] ⏭️ Skipping initialSession (just handled signedIn)');
        }
        return;
      }

      _lastEvent = eventName;

      OAuthEntry.clearGuardIfSignedIn(data);

      switch (data.event) {
        case AuthChangeEvent.signedIn:
          _manualSignOutOnce = false;
          _signOutDebounce?.cancel();

          // ✅ [ProfilePage修复] 判断是否需要force（在执行异步操作前）
          final needsForceNav =
              _lastRoute == '/home' || _lastRoute == '/welcome';

          if (kDebugMode && needsForceNav) {
            debugPrint(
                '[AuthFlowObserver] 🔄 OAuth login detected, will force navigation');
          }

          // ✅ 立即开始导航（不等待Profile预热）
          final navFuture = _goOnce('/home', force: needsForceNav);

          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            // ✅ [时序优化] 导航和初始化并行进行
            await Future.wait([
              navFuture,
              Future(() async {
                try {
                  await NotificationService.subscribeUser(user.id);
                } catch (_) {}

                // ✅ [方案四] Profile预热
                await _preheatProfile(user);

                try {
                  final code = RegisterScreen.pendingInvitationCode;
                  if (code != null && code.isNotEmpty) {
                    await RewardService.submitInviteCode(
                        code.trim().toUpperCase());
                    RegisterScreen.clearPendingCode();
                  }
                } catch (_) {}
              }),
            ]);
          } else {
            await navFuture;
          }

          if (kDebugMode) {
            debugPrint(
                '[AuthFlowObserver] ✅ Navigation and initialization completed');
          }
          break;

        case AuthChangeEvent.initialSession:
          _manualSignOutOnce = false;

          final hasSession =
              Supabase.instance.client.auth.currentSession != null;

          if (hasSession) {
            // ✅ [竞态修复] 优先检查 _everNavigated
            if (_everNavigated) {
              if (kDebugMode) {
                debugPrint(
                    '[AuthFlowObserver] 🔥 Already navigated (_everNavigated=true)');
                debugPrint(
                    '[AuthFlowObserver] ✅ Skipping all navigation (preventing duplicate)');
              }

              final user = Supabase.instance.client.auth.currentUser;
              if (user != null) {
                // ✅ [方案四] 仍然预热 Profile（但不导航）
                await _preheatProfile(user);

                try {
                  await NotificationService.subscribeUser(user.id);
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint(
                        '[AuthFlowObserver] subscribeUser (skip nav) error: $e');
                  }
                }
              }

              _initialNavigationDone = true;
              return;
            }

            final user = Supabase.instance.client.auth.currentUser;
            if (user != null) {
              // ✅ [方案四] 冷启动时预热 Profile
              await _preheatProfile(user);

              try {
                await NotificationService.subscribeUser(user.id);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                      '[AuthFlowObserver] subscribeUser (initialSession) error: $e');
                }
              }
            }

            if (_guard.isHandlingDeepLink) {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] 🔒 Guard 保护激活中，等待深链完成...');
              }

              for (int i = 0; i < 30; i++) {
                await Future.delayed(const Duration(milliseconds: 100));
                if (!_guard.isHandlingDeepLink) break;
              }
            }

            if (kDebugMode) {
              debugPrint('[AuthFlowObserver] ⏳ 等待深链服务（iOS 已登录场景）...');
            }
            await Future.delayed(
                Duration(milliseconds: Platform.isIOS ? 1500 : 500));

            final currentRoute = await _getCurrentRouteWithRetry(
              maxRetries: 5,
              delayMs: 100,
            );

            if (kDebugMode) {
              debugPrint(
                  '[AuthFlowObserver] initialSession check (logged in):');
              debugPrint('  currentRoute: $currentRoute');
              debugPrint('  _everNavigated: $_everNavigated');
              debugPrint(
                  '  Guard.wasRecentDeepLink: ${_guard.wasRecentDeepLink}');
            }

            if (_guard.wasRecentDeepLink) {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] 🔗 检测到最近的深链活动');
              }

              if (currentRoute != null &&
                  currentRoute != '/' &&
                  currentRoute != '/welcome' &&
                  currentRoute != '/home') {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] ✅ 保留深链目标页面: $currentRoute');
                }
                _everNavigated = true;
                _initialNavigationDone = true;
                return;
              }
            }

            if (currentRoute != null &&
                currentRoute != '/' &&
                currentRoute != '/welcome' &&
                currentRoute != '/home') {
              if (kDebugMode) {
                debugPrint(
                    '[AuthFlowObserver] 🎯 Already on business page: $currentRoute');
                debugPrint(
                    '[AuthFlowObserver] ✅ Skipping navigation (respecting business state)');
              }

              _everNavigated = true;
              _initialNavigationDone = true;
              return;
            }

            if (currentRoute == '/' || currentRoute == '/home') {
              if (kDebugMode) {
                debugPrint(
                    '[AuthFlowObserver] ✅ Already on home page: $currentRoute');
                debugPrint(
                    '[AuthFlowObserver] ✅ Skipping navigation (preserving page state)');
                debugPrint(
                    '[AuthFlowObserver] 📌 User interactions during skeleton screen will be preserved');
              }

              _everNavigated = true;
              _initialNavigationDone = true;
              return;
            }

            if (kDebugMode) {
              debugPrint(
                  '[AuthFlowObserver] 🚀 Navigating from $currentRoute to /home');
            }

            await _goOnce('/home');
          } else {
            // ✅ [竞态修复] 未登录场景也检查 _everNavigated
            if (_everNavigated) {
              if (kDebugMode) {
                debugPrint(
                    '[AuthFlowObserver] 🔥 Already navigated (no session, _everNavigated=true)');
                debugPrint(
                    '[AuthFlowObserver] ✅ Skipping all navigation (preserving current page)');
              }
              return;
            }

            Uri? initialLink;
            try {
              initialLink = await AppLinks().getInitialLink();
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] getInitialLink error: $e');
              }
            }

            final isOAuthReturn = OAuthEntry.isOAuthCallback(initialLink);

            if (kDebugMode) {
              debugPrint('[AuthFlowObserver] initialSession: no session, '
                  'inFlight=${OAuthEntry.inFlight}, '
                  'isOAuthReturn=$isOAuthReturn, '
                  'initialLink=$initialLink');
            }

            var spins = 0;
            final maxSpins = 6;
            final shouldInitiallyWait = OAuthEntry.inFlight || isOAuthReturn;

            if (shouldInitiallyWait) {
              debugPrint('[AuthFlowObserver] Waiting for OAuth callback...');
            }

            while (spins < maxSpins) {
              if (!OAuthEntry.inFlight && !isOAuthReturn) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] OAuth cleared, stopping wait');
                }
                break;
              }

              if (Supabase.instance.client.auth.currentSession != null) {
                if (kDebugMode) {
                  debugPrint(
                      '[AuthFlowObserver] Session appeared during wait (${spins * 300}ms), breaking');
                }
                break;
              }

              if (shouldInitiallyWait) {
                if (kDebugMode && spins % 2 == 0) {
                  debugPrint(
                      '[AuthFlowObserver] Wait OAuth... inFlight=${OAuthEntry.inFlight} isOAuthReturn=$isOAuthReturn (${spins * 300}ms)');
                }
                await Future.delayed(const Duration(milliseconds: 300));
                spins++;
              } else {
                break;
              }
            }

            if (Supabase.instance.client.auth.currentSession != null) {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] Session found after OAuth wait, '
                    'delegating to signedIn event');
              }
            } else {
              final deepLinkService = DeepLinkService.instance;

              if (_guard.isHandlingDeepLink) {
                if (kDebugMode) {
                  debugPrint(
                      '[AuthFlowObserver] 🔒 Guard 保护激活中（未登录场景），等待深链完成...');
                }

                for (int i = 0; i < 30; i++) {
                  await Future.delayed(const Duration(milliseconds: 100));
                  if (!_guard.isHandlingDeepLink) break;
                }
              }

              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] ⏳ 等待深链服务初始化（iOS 安全等待）...');
              }

              await Future.delayed(
                  Duration(milliseconds: Platform.isIOS ? 1500 : 600));

              if (deepLinkService.isHandlingInitialLink) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] 🔗 检测到深链正在处理，等待完成...');
                }

                try {
                  await deepLinkService.initialLinkFuture?.timeout(
                    const Duration(seconds: 5),
                    onTimeout: () {
                      if (kDebugMode) {
                        debugPrint('[AuthFlowObserver] ⚠️ 深链超时，继续鉴权流程');
                      }
                    },
                  );
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('[AuthFlowObserver] ❌ 等待深链错误: $e');
                  }
                }
              }

              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] ⏳ 等待路由切换完成...');
              }
              await Future.delayed(
                  Duration(milliseconds: Platform.isIOS ? 1000 : 400));

              if (_guard.isHandlingDeepLink) {
                if (kDebugMode) {
                  debugPrint(
                      '[AuthFlowObserver] 🔒 等待后发现 Guard 仍在处理（未登录），继续等待...');
                }

                for (int i = 0; i < 30; i++) {
                  await Future.delayed(const Duration(milliseconds: 100));
                  if (!_guard.isHandlingDeepLink) {
                    if (kDebugMode) {
                      debugPrint(
                          '[AuthFlowObserver] ✅ Guard 完成（未登录），用时 ${i * 100}ms');
                    }
                    break;
                  }
                }

                await Future.delayed(const Duration(milliseconds: 200));
              }

              final currentRoute = await _getCurrentRouteWithRetry(
                maxRetries: 5,
                delayMs: 100,
              );

              if (kDebugMode) {
                debugPrint(
                    '[AuthFlowObserver] initialSession check (not logged in):');
                debugPrint(
                    '  hasNavigatedViaDeepLink: ${deepLinkService.hasNavigatedViaDeepLink}');
                debugPrint('  currentRoute: $currentRoute');
                debugPrint(
                    '  Guard.isHandlingDeepLink: ${_guard.isHandlingDeepLink}');
                debugPrint(
                    '  Guard.wasRecentDeepLink: ${_guard.wasRecentDeepLink}');
              }

              if (_guard.wasRecentDeepLink) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] 🔗 Guard 检测到最近的深链活动（未登录）');
                }

                if (currentRoute != null &&
                    currentRoute != '/' &&
                    currentRoute != '/welcome') {
                  if (kDebugMode) {
                    debugPrint('[AuthFlowObserver] ✅ 保留深链目标页面: $currentRoute');
                    debugPrint('[AuthFlowObserver] ✅ 跳过欢迎页导航（用户可以 guest 模式浏览）');
                  }
                  _everNavigated = true;
                  _initialNavigationDone = true;
                  return;
                }
              }

              if (deepLinkService.hasNavigatedViaDeepLink) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] 🔗 深链服务已标记导航完成（未登录）');
                }

                if (currentRoute != null &&
                    currentRoute != '/' &&
                    currentRoute != '/welcome') {
                  if (kDebugMode) {
                    debugPrint('[AuthFlowObserver] ✅ 保留深链目标页面: $currentRoute');
                    debugPrint('[AuthFlowObserver] 📌 用户可在未登录状态浏览商品');
                  }

                  _everNavigated = true;
                  _initialNavigationDone = true;
                  return;
                }
              }

              if (currentRoute != null &&
                  currentRoute != '/' &&
                  currentRoute != '/welcome') {
                if (kDebugMode) {
                  debugPrint(
                      '[AuthFlowObserver] 🎯 发现已在业务页面（未登录）: $currentRoute');
                  debugPrint('[AuthFlowObserver] ✅ 保留业务页面（最后防线）');
                }

                _everNavigated = true;
                _initialNavigationDone = true;
                return;
              }

              if (kDebugMode) {
                debugPrint(
                    '[AuthFlowObserver] No deep link navigation detected');
                debugPrint('[AuthFlowObserver] 🚀 Going to welcome page');
              }

              try {
                OAuthEntry.finish();
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                      '[AuthFlowObserver] OAuthEntry.finish() error: $e');
                }
              }

              await _goOnce('/welcome');
            }
          }
          break;

        case AuthChangeEvent.userUpdated:
          _manualSignOutOnce = false;
          break;

        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
          try {
            await NotificationService.unsubscribe();
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[AuthFlowObserver] unsubscribe error: $e');
            }
          }

          _signOutDebounce?.cancel();

          if (_lastUserId != null) {
            ProfileService.i.invalidateCache(_lastUserId!);
            _lastUserId = null;
          }

          if (_manualSignOutOnce) {
            debugPrint(
                '[AuthFlowObserver] signedOut fast-path (manual). swallow nav once.');
            _manualSignOutOnce = false;
            break;
          }

          final now = DateTime.now();
          final fast = _manualSignOutAt != null &&
              now.difference(_manualSignOutAt!).inSeconds <= 3;

          if (fast) {
            _manualSignOutAt = null;
            if (!isGraceWindowSignOut) {
              await _goOnce('/login');
            } else {
              debugPrint(
                  '[AuthFlowObserver] grace-window: skip fast-path navigation');
            }
            break;
          }

          if (isGraceWindowSignOut) {
            debugPrint(
                '[AuthFlowObserver] grace-window: cleanup done, skip debounced navigation');
            break;
          }

          _signOutDebounce = Timer(const Duration(milliseconds: 150), () async {
            await _goOnce('/login');
          });
          break;

        default:
          break;
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _signOutDebounce?.cancel();
    _sub = null;
    _signOutDebounce = null;
    _started = false;
  }
}
