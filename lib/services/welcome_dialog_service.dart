// lib/services/welcome_dialog_service.dart
//
// Final version – Swaply Welcome Dialog Service (方案A)
//
// 特点：
//  1) 完全依赖 RewardService.ensureWelcomeForCurrentUser() 的 shouldPopup 决策。
//  2) 不查询 user_coupons，不重复查询 coupons，只用一次精准查询（coupon_id）。
//  3) 与 main.dart / AuthFlowObserver 完美联动。
//  4) 永不重复弹：会话级 + 本地永久标记。
//  5) 全面压缩逻辑，删除所有历史残留代码。
// ---------------------------------------------------------------------

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/services/reward_service.dart';
import 'package:swaply/widgets/welcome_coupon_dialog.dart';

class WelcomeDialogService {
  WelcomeDialogService._();

  // ===== 会话级去重（当前运行期间只弹一次）=====
  static final Map<String, bool> _shownSession = {};

  // ===== 并发保护（对话框正在展示） =====
  static bool _isShowing = false;

  // ===== 队列 & 反重入控制（新增） =====
  static bool _scheduled = false;
  static bool _inFlight = false;

  // ===== 本地持久化 Key =====
  static String _shownKey(String uid) => 'welcome_popup_shown_$uid';

  /// 外部统一入口（新增反重入护栏）
  static Future<void> maybeShow(BuildContext context) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      return await _showIfNeeded(context, force: false);
    } finally {
      _inFlight = false;
    }
  }

  /// 首帧后调用（推荐）——改为非阻塞排队，避免与首帧导航竞争
  static Future<void> scheduleCheck(BuildContext context) async {
    if (_scheduled || _inFlight) return;
    _scheduled = true;
    // 让出当前任务队列，再稍等 200ms，避免与首帧导航/深链抢占
    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      _scheduled = false;
      // ignore: use_build_context_synchronously
      await maybeShow(context); // 真正的检查/弹窗仍在 maybeShow 里
    });
  }

  // ================================================================
  // 核心逻辑
  // ================================================================
  static Future<void> _showIfNeeded(
      BuildContext context, {
        required bool force,
      }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final uid = user.id;

    // ---- 1) 会话级去重 ----
    if (!force && _shownSession[uid] == true) {
      if (kDebugMode) print('[WelcomeDialog] session already shown');
      return;
    }

    // ---- 2) 历史永久去重 ----
    final prefs = await SharedPreferences.getInstance();
    final shownEver = prefs.getBool(_shownKey(uid)) == true;
    if (!force && shownEver) {
      if (kDebugMode) print('[WelcomeDialog] already shown historically');
      _shownSession[uid] = true;
      return;
    }

    // ---- 3) 询问 RewardService（决定是否弹）----
    EnsureWelcomeResult result;
    try {
      result = await RewardService.ensureWelcomeForCurrentUser();
    } catch (e) {
      if (kDebugMode) print('[WelcomeDialog] RPC failed: $e');
      return;
    }

    if (!force && !result.shouldPopup) {
      if (kDebugMode) print('[WelcomeDialog] shouldPopup=false -> skip');
      _shownSession[uid] = true;
      return;
    }

    // ---- 4) 精准查询欢迎券 ----
    final couponId = result.couponId;
    if (couponId == null || couponId.isEmpty) {
      if (kDebugMode) print('[WelcomeDialog] no coupon id -> skip');
      _shownSession[uid] = true;
      await prefs.setBool(_shownKey(uid), true);
      return;
    }

    Map<String, dynamic>? row;
    try {
      final r = await client
          .from('coupons')
          .select(
          'id, code, title, description, expires_at, type, status, user_id')
          .eq('id', couponId)
          .maybeSingle();

      if (r == null) {
        if (kDebugMode) print('[WelcomeDialog] coupon missing -> skip');
        _shownSession[uid] = true;
        await prefs.setBool(_shownKey(uid), true);
        return;
      }

      row = Map<String, dynamic>.from(r);
    } catch (e) {
      if (kDebugMode) print('[WelcomeDialog] coupon query error: $e');
      return;
    }

    // ---- 5) 防重复弹 ----
    if (_isShowing) return;
    _isShowing = true;

    try {
      await Future.delayed(const Duration(milliseconds: 180));
      if (!context.mounted) return;

      if (kDebugMode) print('[WelcomeDialog] showing popup...');

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => WelcomeCouponDialog(couponData: row!),
      );

      // ---- 6) 关闭后记录永久标记 ----
      await prefs.setBool(_shownKey(uid), true);
      _shownSession[uid] = true;

      if (kDebugMode) print('[WelcomeDialog] popup finished');
    } finally {
      _isShowing = false;
    }
  }

  // ================================================================
  // 调试方法
  // ================================================================
  static Future<void> resetFor(String uid) async {
    _shownSession.remove(uid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shownKey(uid));
    if (kDebugMode) print('[WelcomeDialog] reset for $uid');
  }

  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
    prefs.getKeys().where((k) => k.startsWith('welcome_popup_shown_')).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    _shownSession.clear();
    if (kDebugMode) print('[WelcomeDialog] reset all (${keys.length} keys)');
  }
}
