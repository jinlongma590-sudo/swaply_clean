// lib/widgets/ios_insets_guard.dart
import 'dart:io';
import 'package:flutter/material.dart';

/// iOS 真机上常见的额外顶部留白（SafeArea/系统插入的双重 padding）清理器。
/// 只移除“顶端”留白；底部不动，避免挡住 Home Indicator / 底部导航。
class IosInsetsGuard extends StatelessWidget {
  final Widget child;
  const IosInsetsGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return child;

    final mq = MediaQuery.of(context);
    final fixed = mq.copyWith(
      padding: mq.padding.copyWith(top: 0.0),
      viewPadding: mq.viewPadding.copyWith(top: 0.0),
      // viewInsets 顶部一般为 0，这里顺手对齐
      viewInsets: mq.viewInsets.copyWith(top: 0.0),
      textScaler: const TextScaler.linear(1.0),
    );
    return MediaQuery(
      data: fixed,
      child: SafeArea(top: false, child: child),
    );
  }
}
