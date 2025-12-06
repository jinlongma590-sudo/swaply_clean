// lib/services/auth_flow_observer.dart
// ✅ [通知架构修复] 完整版：订阅生命周期收口到 AuthFlowObserver
// ✅ [iOS 竞态修复] initialSession 增加协调等待，避免与 DeepLinkService 竞争
// ✅ [协调机制] 检查 DeepLinkService 标志，等待业务深链处理完成
// [完整修复版] OAuth导航优化 + 首次导航标志
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'package:swaply/router/root_nav.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/oauth_entry.dart';
import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/services/deep_link_service.dart'; // ✅ [协调机制] 引入 DeepLinkService
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

  // ✅ [闪屏修复] 全局标志：首次导航是否完成
  static bool _initialNavigationDone = false;

  // ✅ [关键] Public getter，供外部访问
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
    _lastRoute = route;
    _lastAt = now;
    return false;
  }

  Future<void> _goOnce(String route) async {
    if (_navigating) return;
    if (_throttle(route)) return;

    _navigating = true;
    debugPrint('[AuthFlowObserver] NAV -> $route');

    SchedulerBinding.instance.addPostFrameCallback((_) {
      navReplaceAll(route);
    });

    await Future.delayed(const Duration(milliseconds: 120));
    _navigating = false;
    _everNavigated = true;

    // ✅ [闪屏修复] 标记首次导航完成
    _initialNavigationDone = true;
  }

  void _preheatProfile(User user) {
    _lastUserId = user.id;
    unawaited(ProfileService.i.getMyProfile());
  }

  void _armBootWatchdogOnce() {
    if (_bootWatchdogArmed) return;
    _bootWatchdogArmed = true;
    _everNavigated = true;
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

      // ✅ [通知架构修复] 修改1：改为标志，不要 return
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

          // ✅ [OAuth闪屏修复] 增加短暂延迟，让MainNavigationPage有时间准备
          await Future.delayed(const Duration(milliseconds: 150));
          await _goOnce('/home');
          break;

        case AuthChangeEvent.initialSession:
          _manualSignOutOnce = false;

          final hasSession =
              Supabase.instance.client.auth.currentSession != null;

          if (hasSession) {
            final user = Supabase.instance.client.auth.currentUser;
            if (user != null) {
              _preheatProfile(user);

              // ✅ [通知架构修复] 修改2：冷启动时订阅
              try {
                await NotificationService.subscribeUser(user.id);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] subscribeUser (initialSession) error: $e');
                }
              }
            }

            // ============================================================
            // ✅ [协调机制] 等待 DeepLinkService 完成业务深链处理
            // 架构符合：
            // - 不检查深链内容（职责分离）
            // - 只检查标志：DeepLinkService 是否正在处理业务深链
            // - 等待完成后再执行全局导航，避免冲突
            // ============================================================
            if (DeepLinkService.isHandlingBusinessDeepLink) {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] 🚦 DeepLinkService is handling business deep link, waiting...');
              }

              // 轮询等待，最多 1 秒
              var waited = 0;
              const checkInterval = 50; // 每 50ms 检查一次
              const maxWait = 1000; // 最多等待 1000ms

              while (DeepLinkService.isHandlingBusinessDeepLink && waited < maxWait) {
                await Future.delayed(const Duration(milliseconds: checkInterval));
                waited += checkInterval;

                if (kDebugMode && waited % 200 == 0) {
                  debugPrint('[AuthFlowObserver] 🕐 Still waiting for business deep link... (${waited}ms)');
                }
              }

              if (DeepLinkService.isHandlingBusinessDeepLink) {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] ⚠️ Timeout waiting for deep link (${waited}ms), proceeding anyway');
                }
              } else {
                if (kDebugMode) {
                  debugPrint('[AuthFlowObserver] ✅ Business deep link handled (waited ${waited}ms)');
                }
              }
            } else {
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] ℹ️ No business deep link detected, proceeding normally');
              }
            }

            // 继续正常的 /home 导航
            // DeepLinkService 的 navPush 会保留在栈上
            await _goOnce('/home');
          } else {
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

              // ✅ [iOS 竞态修复] 未登录时，稍微延迟跳转 /welcome
              // 避免和 DeepLinkService 的初始化竞态
              // 如果此时有 deep link 正在处理，先让它完成
              if (kDebugMode) {
                debugPrint('[AuthFlowObserver] No session, delaying /welcome by 150ms to avoid deep link race');
              }
              await Future.delayed(const Duration(milliseconds: 150));

              await _goOnce('/welcome');
            }
          }
          break;

        case AuthChangeEvent.userUpdated:
          _manualSignOutOnce = false;
          break;

        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.userDeleted:
        // ✅ [通知架构修复] 修改3：永远清理订阅（无论如何都执行）
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

          // 状态机：手动登出
          if (_manualSignOutOnce) {
            debugPrint('[AuthFlowObserver] signedOut fast-path (manual). swallow nav once.');
            _manualSignOutOnce = false;
            break;
          }

          // 状态机：快速登出
          final now = DateTime.now();
          final fast = _manualSignOutAt != null &&
              now.difference(_manualSignOutAt!).inSeconds <= 3;

          if (fast) {
            _manualSignOutAt = null;
            // ✅ grace-window 判断：只在这里拦截快速登出的导航
            if (!isGraceWindowSignOut) {
              await _goOnce('/login');
            } else {
              debugPrint('[AuthFlowObserver] grace-window: skip fast-path navigation');
            }
            break;
          }

          // ✅ grace-window 判断：拦截延迟导航
          if (isGraceWindowSignOut) {
            debugPrint('[AuthFlowObserver] grace-window: cleanup done, skip debounced navigation');
            break;
          }

          // 正常的延迟导航
          _signOutDebounce =
              Timer(const Duration(milliseconds: 150), () async {
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