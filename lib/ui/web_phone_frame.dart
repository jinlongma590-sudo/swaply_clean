// lib/ui/web_phone_frame.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebPhoneFrame extends StatelessWidget {
  const WebPhoneFrame({
    super.key,
    required this.child,
    this.maxPhoneWidth = 480, // 可改 414/428/480
  });

  final Widget child;
  final double maxPhoneWidth;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child; // 真机不受影响

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxPhoneWidth),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.0), // 锁字重
          ),
          child: child,
        ),
      ),
    );
  }
}
