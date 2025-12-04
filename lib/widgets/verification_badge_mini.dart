import 'package:flutter/material.dart';
import '../models/verification_types.dart';

class VerificationBadgeMini extends StatelessWidget {
  final VerificationBadgeType type;
  const VerificationBadgeMini({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    if (type == VerificationBadgeType.none) return const SizedBox.shrink();

    IconData icon = Icons.verified;
    String text = VerificationBadgeUtil.label(type);

    if (type.isOfficial) icon = Icons.verified; // 你也可换成不同图标
    if (type.isPremium) icon = Icons.workspace_premium;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
