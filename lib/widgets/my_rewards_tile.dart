// lib/widgets/my_rewards_tile.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/reward_service.dart';
import 'package:swaply/pages/task_management_page.dart';
// import 'package:swaply/router/root_nav.dart'; // 不再需要
import 'package:swaply/router/safe_navigator.dart';

class MyRewardsTile extends StatefulWidget {
  const MyRewardsTile({super.key});

  @override
  State<MyRewardsTile> createState() => _MyRewardsTileState();
}

class _MyRewardsTileState extends State<MyRewardsTile> {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  void _initFuture() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    _future = (uid == null)
        ? Future.value(<String, dynamic>{})
        : RewardService.getSummary(userId: uid);
  }

  Future<void> _refresh() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() {
      _future = RewardService.getSummary(userId: uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        // Loading
        if (snap.connectionState == ConnectionState.waiting) {
          return _tileShell(
            iconBg: const Color(0xFF7C3AED).withOpacity(0.10),
            iconColor: const Color(0xFF7C3AED),
            title: 'My Rewards',
            // ✅ 隐藏副标题
            subtitle: null,
            trailing: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            onTap: null,
          );
        }

        // Error
        if (snap.hasError) {
          return _tileShell(
            iconBg: const Color(0xFF7C3AED).withOpacity(0.10),
            iconColor: const Color(0xFF7C3AED),
            title: 'My Rewards',
            // ✅ 隐藏副标题
            subtitle: null,
            trailing: IconButton(
              tooltip: 'Retry',
              icon: const Icon(Icons.refresh_rounded, size: 20, color: Colors.grey),
              onPressed: _refresh,
            ),
            onTap: _refresh,
          );
        }

        // Normal
        // 这里虽然仍然计算了 points/coupons，但不再展示
        final data = snap.data ?? const <String, dynamic>{};
        final points = _pickInt(data, ['points', 'total_points', 'point', 'totalPoints']);
        final coupons = _pickInt(data, ['coupons', 'couponCount', 'coupon_count', 'total_coupons']);
        // 如果后续想用到 points/coupons，可在这里根据需要拼接文案

        return _tileShell(
          iconBg: const Color(0xFF7C3AED).withOpacity(0.10),
          iconColor: const Color(0xFF7C3AED),
          title: 'My Rewards',
          // ✅ 隐藏副标题（不再显示 Points/Coupons）
          subtitle: null,
          trailing: Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey[400]),
          onTap: () {
            SafeNavigator.push(MaterialPageRoute(builder: (_) => const TaskManagementPage()));
          },
        );
      },
    );
  }

  /// 统一外观的条目容器
  Widget _tileShell({
    required Color iconBg,
    required Color iconColor,
    required String title,
    String? subtitle, // ✅ 改为可空；为空时不渲染副标题
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.emoji_events_rounded, color: iconColor, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ),
    );
  }

  int _pickInt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) {
        final p = int.tryParse(v);
        if (p != null) return p;
      }
    }
    return 0;
  }
}
