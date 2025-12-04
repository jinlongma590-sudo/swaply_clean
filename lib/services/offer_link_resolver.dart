// lib/services/offer_link_resolver.dart
//
// 解析通知，产出：route + arguments（不做导航，只做解析）
// - 优先解析 offer → 跳转到 /offer-detail（带 offerId 与可选 listingId）
// - 其次解析 listing → 跳转到 /listing（参数为 listingId 字符串）
// - 兼容字段来源：顶层字段 / payload / metadata
//
// 用法（示例，在 notification_page.dart 中点击时）：
//   final target = OfferLinkResolver.resolve(notification);
//   if (target != null) {
//     await navPush(target.route, arguments: target.arguments);
//   } else {
//     _showSnack('Cannot open: missing target', isError: true);
//   }

typedef ResolvedRoute = ({String route, Object? arguments});

class OfferLinkResolver {
  /// 解析一条通知，返回路由与参数；无法解析则返回 null
  static ResolvedRoute? resolve(Map<String, dynamic> n) {
    final type = _str(n['type']) ?? '';

    // 统一提取 listingId / offerId（多来源兜底）
    final listingId = _firstNonEmpty([
      _str(n['listing_id']),
      _str((n['payload'] as Map?)?['listing_id']),
      _str((n['metadata'] as Map?)?['listing_id']),
    ]);

    final offerId = _firstNonEmpty([
      _str(n['offer_id']),
      _str((n['payload'] as Map?)?['offer_id']),
      _str((n['metadata'] as Map?)?['offer_id']),
    ]);

    // 1) Offer 优先：跳到 Offer Detail
    if (type == 'offer' && _notEmpty(offerId)) {
      // 这里约定路由为 '/offer-detail'；若你的 AppRouter 用的是其它名字，改成你的即可
      return (
      route: '/offer-detail',
      arguments: <String, Object?>{
        'offerId': offerId, // String? → Object? OK
        if (_notEmpty(listingId)) 'listingId': listingId,
      },
      );
    }

    // 2) 普通消息/心愿单/价格变动等：跳到商品详情
    if (_notEmpty(listingId)) {
      return (
      route: '/listing',
      // 你的 listing 详情目前是直接用 String 作为 arguments
      arguments: listingId,
      );
    }

    // 3) 兜底失败
    return null;
  }

  /// 将任意 Object? 转为非空白字符串；无效则返回 null
  static String? _str(Object? v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is num || v is bool) {
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }
    return null;
  }

  /// 返回列表中第一个非空、非空白字符串
  static String? _firstNonEmpty(List<String?> items) {
    for (final s in items) {
      if (s != null && s.trim().isNotEmpty) return s;
    }
    return null;
  }

  static bool _notEmpty(String? s) => s != null && s.trim().isNotEmpty;
}
