// lib/pages/reward_center_page.dart
// 入口壳：保持文件名和对外接口不变，实际内容由 RewardCenterHub 承载

import 'package:flutter/material.dart';
import 'package:swaply/rewards/reward_center_hub.dart';

class RewardCenterPage extends StatelessWidget {
  final int initialTab;

  const RewardCenterPage({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    // 直接返回 Hub 页面
    return RewardCenterHub(initialTab: initialTab);
  }
}