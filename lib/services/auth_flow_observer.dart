// lib/services/auth_flow_observer.dart
// ✅ [iOS 竞态修复] initialSession 增加延迟，避免与 DeepLinkService 竞争
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

      if (sinceStart < const Duration(milliseconds: 1200) &&
          data.event == AuthChangeEvent.signedOut) {
        debugPrint(
            '[AuthFlowObserver] grace-window ignore early ${data.event}');
        return;
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
            if (user != null) _preheatProfile(user);

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
            await _goOnce('/login');
            break;
          }

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