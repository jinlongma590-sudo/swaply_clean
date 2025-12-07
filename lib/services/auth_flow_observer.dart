// lib/services/auth_flow_observer.dart
// ✅ [骨架屏修复] 优化 initialSession 逻辑，避免不必要的页面重建
// ✅ [架构修复] AuthFlowObserver 成为真正的"智能协调器"
// ✅ [业务状态尊重] 在导航前检查当前路由，不破坏业务页面
// ✅ [深链协调] 与 DeepLinkService 完美配合，避免导航冲突
// ✅ [用户体验] 保护用户主动导航，避免强制跳转

import 'dart:async';
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

  /// ✅ [骨架屏修复] 优化获取当前路由逻辑
  String? _getCurrentRoute() {
    try {
      final navigator = rootNavKey.currentState;
      if (navigator == null) {
        if (kDebugMode) {
          debugPrint('[AuthFlowObserver] _getCurrentRoute: navigator is null, returning cached: $_lastRoute');
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

      // ✅ [关键修复] 如果无法获取路由名，但 navigator 存在且已渲染
      // 很可能是在 initialRoute（/），应该返回 '/' 而不是 null
      if (navigator.context.mounted && _lastRoute == null) {
        if (kDebugMode) {
          debugPrint('[AuthFlowObserver] _getCurrentRoute: likely on initialRoute, returning "/"');
        }
        return '/';
      }

      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] _getCurrentRoute: returning cached: $_lastRoute');
      }
      return _lastRoute;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] _getCurrentRoute error: $e');
      }
      return _lastRoute;
    }
  }

  Future<void> _goOnce(String route) async {
    if (_navigating) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ⏭️ Navigation already in progress, skipping');
      }
      return;
    }

    if (_throttle(route)) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ⏭️ Throttled navigation to $route (too soon)');
      }
      return;
    }

    final currentRoute = _getCurrentRoute();
    if (currentRoute == route) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ⏭️ Already on $route, skip navigation');
        debugPrint('[AuthFlowObserver] 📌 Preserving scroll position and page state');
      }
      _everNavigated = true;
      _initialNavigationDone = true;
      return;
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
        debugPrint('[AuthFlowObserver] ⏳ Waiting for navigation ready... (${waited}ms)');
      }
    }

    if (rootNavKey.currentState == null) {
      if (kDebugMode) {
        debugPrint('[AuthFlowObserver] ❌ Navigation timeout! rootNavKey.currentState is null');
      }
      _navigating = false;
      return;
    }

    if (kDebugMode) {
      debugPrint('[AuthFlowObserver] ✅ Navigation ready (waited ${waited}ms), executing navReplaceAll');
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
    _everNavigated = true;
    _initialNavigationDone = true;
  }

  void _preheatProfile(User user) {
    _lastUserId = user.id;
    unawaited(ProfileService.i.getMyProfile());
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

      final isGraceWindowSignOut = sinceStart < const Duration(milliseconds: 1200) &&
          data.event == AuthChangeEvent.signedOut;

      if (isGraceWindowSignOut) {
        debugPrint('[AuthFlowObserver] grace-window signedOut detected (will skip navigation but allow cleanup)');
      }

      final eventName = data.event.name;
      if (_lastEvent == 'signedIn' && eventName == 'initialSession') return;
      _lastEvent = eventName;

      OAuthEntry.clearGuardIfSignedIn(data);

      switch (data.event) {
      // ============================================================
      // CASE: signedIn（登录成功）
      // ============================================================
        case AuthChangeEvent.signedIn:
          _manualSignOutOnce = false;
          _signOutDebounce?.cancel();

          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            try {
              await NotificationService.subscribeUser(user.id);
            } catch (_) {}
            _preheatProfile(user);

            try {
              final code = RegisterScreen.pendingInvitationCode;
              if (code != null && code.isNotEmpty) {
                await RewardService.submitInviteCode(code.trim().toUpperCase());
                RegisterScreen.clearPendingCode();
              }
            } catch (_) {}
          }

          await Future.delayed(const Duration(milliseconds: 150));
          await _goOnce('/home');
          break;

      // ============================================================
      // CASE: initialSession（冷启动）
      // ✅ [骨架屏修复] 优化导航逻辑，避免不必要的页面重建
      // ============================================================
        case AuthChangeEvent.initialSession:
          _manualSignOutOnce = false;

          final hasSession = Supabase.instance.client.auth.currentSession != null;

          if (hasSession) {
            // ✅ 步骤 1：预热 Profile 和订阅通知
            final user = Supabase.instance.client.auth.currentUser;
            if (user != null) {
              _preheatProfile(user);

              try {
                await NotificationService.subscribeUser(user.id);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] subscribeUser (initialSession) error: $e');
                }
              }
            }

            // ============================================================
            // ✅ [关键修复] 步骤 2：智能检查当前路由状态
            // 避免在用户已经在首页时重新导航，防止状态丢失
            // ============================================================
            final currentRoute = _getCurrentRoute();

            if (kDebugMode) {
              debugPrint('[AuthFlowObserver] initialSession check:');
              debugPrint('  currentRoute: $currentRoute');
              debugPrint('  _everNavigated: $_everNavigated');
            }

            // ✅ 情况 1：已经在业务页面（由深链接导航）
            if (currentRoute != null &&
                currentRoute != '/' &&
                currentRoute != '/welcome') {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] 🎯 Already on business page: $currentRoute');
                debugPrint('[AuthFlowObserver] ✅ Skipping navigation (respecting business state)');
              }

              _everNavigated = true;
              _initialNavigationDone = true;
              return;
            }

            // ✅ [关键修复] 情况 2：已经在首页（/ 或 /home）
            // 这是骨架屏场景：用户在 MainNavigationPage 内部交互，路由仍是 / 或 /home
            // 不应该重新导航，否则会重建页面并丢失用户状态（滚动位置、Tab选择等）
            if (currentRoute == '/' || currentRoute == '/home') {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] ✅ Already on home page: $currentRoute');
                debugPrint('[AuthFlowObserver] ✅ Skipping navigation (preserving page state)');
                debugPrint('[AuthFlowObserver] 📌 User interactions during skeleton screen will be preserved');
              }

              // 标记为已完成导航，避免后续问题
              _everNavigated = true;
              _initialNavigationDone = true;
              return;
            }

            // ✅ 情况 3：在欢迎页或其他需要切换的页面
            if (kDebugMode) {
              debugPrint('[AuthFlowObserver] 🚀 Navigating from $currentRoute to /home');
            }

            await _goOnce('/home');

          } else {
            // ============================================================
            // 无会话流程：等待 OAuth 或跳转 welcome
            // ============================================================
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
                  debugPrint('[AuthFlowObserver] Session appeared during wait (${spins * 300}ms), breaking');
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
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] No session after wait (${spins * 300}ms), '
                    'going to welcome');
              }

              try {
                OAuthEntry.finish();
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] OAuthEntry.finish() error: $e');
                }
              }

              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] No session, delaying /welcome by 150ms to avoid deep link race');
              }
              await Future.delayed(const Duration(milliseconds: 150));

              await _goOnce('/welcome');
            }
          }
          break;

      // ============================================================
      // CASE: userUpdated
      // ============================================================
        case AuthChangeEvent.userUpdated:
          _manualSignOutOnce = false;
          break;

      // ============================================================
      // CASE: signedOut / userDeleted
      // ============================================================
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
            debugPrint('[AuthFlowObserver] signedOut fast-path (manual). swallow nav once.');
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
              debugPrint('[AuthFlowObserver] grace-window: skip fast-path navigation');
            }
            break;
          }

          if (isGraceWindowSignOut) {
            debugPrint('[AuthFlowObserver] grace-window: cleanup done, skip debounced navigation');
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
