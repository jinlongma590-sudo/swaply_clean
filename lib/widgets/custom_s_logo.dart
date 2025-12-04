import 'package:flutter/material.dart';

/// 一个可配置的 S 图标：圆角白底方块 + 蓝色 S + 可选阴影
class CustomSLogo extends StatelessWidget {
  const CustomSLogo({
    super.key,
    this.size = 96,
    this.backgroundColor = Colors.white,
    this.letterColor = const Color(0xFF1E88E5),
    this.showShadow = true,
  });

  /// 外层方块的边长
  final double size;

  /// 方块背景色（默认白色）
  final Color backgroundColor;

  /// 字母 S 的颜色（默认蓝色）
  final Color letterColor;

  /// 是否显示外部投影
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size * 0.2);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: size * 0.16,
                  offset: Offset(0, size * 0.08),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 轻微内阴影/高光，让方块更立体（可选）
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.28),
                    Colors.white.withOpacity(0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),
          // 居中绘制一个加粗的 “S”
          Center(
            child: Text(
              'S',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: letterColor,
                fontSize: size * 0.64, // 字母相对尺寸
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
