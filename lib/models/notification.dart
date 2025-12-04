// lib/models/notification.dart
/// 通知数据模型
class NotificationModel {
  final String id;
  final String recipientId;
  final String? senderId;
  final String type;
  final String title;
  final String message;
  final String? listingId;
  final String? offerId;
  final Map<String, dynamic> metadata;
  final bool isRead;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime? readAt;

  const NotificationModel({
    required this.id,
    required this.recipientId,
    this.senderId,
    required this.type,
    required this.title,
    required this.message,
    this.listingId,
    this.offerId,
    required this.metadata,
    required this.isRead,
    required this.isDeleted,
    required this.createdAt,
    this.readAt,
  });

  /// 从数据库记录创建通知对象
  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'].toString(),
      recipientId: map['recipient_id']?.toString() ?? '',
      senderId: map['sender_id']?.toString(),
      type: map['type']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      listingId: map['listing_id']?.toString(),
      offerId: map['offer_id']?.toString(),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'])
          : <String, dynamic>{},
      isRead: map['is_read'] == true,
      isDeleted: map['is_deleted'] == true,
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      readAt: _parseDateTime(map['read_at']),
    );
  }

  /// 转换为数据库记录
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recipient_id': recipientId,
      'sender_id': senderId,
      'type': type,
      'title': title,
      'message': message,
      'listing_id': listingId,
      'offer_id': offerId,
      'metadata': metadata,
      'is_read': isRead,
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
    };
  }

  /// 便捷：从自身或 metadata 里拿 listingId（用于路由）
  String? get listingIdOrMeta {
    final mid = metadata['listing_id']?.toString();
    return listingId ?? mid;
  }

  /// 便捷：转为详情页可识别的路由参数（兼容多键名）
  Map<String, dynamic> toRouteArguments() {
    final idForRoute = listingIdOrMeta ?? id;
    return {
      // 多种键名都带上，详情页会择优取值
      'id': idForRoute,
      'listing_id': idForRoute,
      'listingId': idForRoute,
      // 附带少量渲染可用信息（不影响后续云端补齐）
      'data': {
        'id': idForRoute,
        'title': listingTitle,
        // 如果 metadata 里带了 images，就顺带给到（可选）
        if (metadata['images'] is List)
          'images': List<String>.from(
            (metadata['images'] as List).map((e) => e.toString()),
          ),
      },
    };
  }

  /// 创建副本，可修改部分字段
  NotificationModel copyWith({
    String? id,
    String? recipientId,
    String? senderId,
    String? type,
    String? title,
    String? message,
    String? listingId,
    String? offerId,
    Map<String, dynamic>? metadata,
    bool? isRead,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      recipientId: recipientId ?? this.recipientId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      listingId: listingId ?? this.listingId,
      offerId: offerId ?? this.offerId,
      metadata: metadata ?? this.metadata,
      isRead: isRead ?? this.isRead,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  /// 获取通知类型的显示文本
  String get typeDisplayText {
    switch (type) {
      case 'offer':
        return 'New Offer';
      case 'wishlist':
        return 'Wishlist';
      case 'purchase':
        return 'Purchase';
      case 'message':
        return 'Message';
      case 'price_drop':
        return 'Price Drop';
      case 'system':
        return 'System';
      default:
        return 'Notification';
    }
  }

  /// 获取通知的图标
  String get iconData {
    switch (type) {
      case 'offer':
        return '💰';
      case 'wishlist':
        return '❤️';
      case 'purchase':
        return '🛒';
      case 'message':
        return '💬';
      case 'price_drop':
        return '📉';
      case 'system':
        return '🔔';
      default:
        return '📬';
    }
  }

  /// 获取通知的颜色（Material Color values）
  int get color {
    switch (type) {
      case 'offer':
        return 0xFF4CAF50; // Green
      case 'wishlist':
        return 0xFFE91E63; // Pink
      case 'purchase':
        return 0xFF2196F3; // Blue
      case 'message':
        return 0xFFFF9800; // Orange
      case 'price_drop':
        return 0xFF9C27B0; // Purple
      case 'system':
        return 0xFF607D8B; // Blue Grey
      default:
        return 0xFF9E9E9E; // Grey
    }
  }

  /// 获取格式化的时间显示
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  /// 获取详细的时间显示
  String get detailedTime {
    final now = DateTime.now();
    final isToday = now.year == createdAt.year &&
        now.month == createdAt.month &&
        now.day == createdAt.day;

    if (isToday) {
      return 'Today ${_formatTime(createdAt)}';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == createdAt.year &&
        yesterday.month == createdAt.month &&
        yesterday.day == createdAt.day;

    if (isYesterday) {
      return 'Yesterday ${_formatTime(createdAt)}';
    }

    return '${createdAt.day}/${createdAt.month}/${createdAt.year} ${_formatTime(createdAt)}';
  }

  /// 是否是重要通知
  bool get isImportant {
    return type == 'offer' || type == 'purchase';
  }

  /// 是否需要用户行动
  bool get requiresAction {
    return type == 'offer' && !isRead;
  }

  /// 获取发送者名称（从metadata中）
  String? get senderName {
    return metadata['sender_name']?.toString() ??
        metadata['buyer_name']?.toString() ??
        metadata['liker_name']?.toString();
  }

  /// 获取相关商品标题（从metadata中）
  String? get listingTitle {
    return metadata['listing_title']?.toString();
  }

  /// 获取报价金额（从metadata中）
  double? get offerAmount {
    final amount = metadata['offer_amount'];
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount);
    return null;
  }

  /// 判断两个通知是否相等
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'NotificationModel(id: $id, type: $type, title: $title, isRead: $isRead)';
  }

  /// 解析日期时间字符串的辅助方法
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// 格式化时间的辅助方法
  static String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// 通知类型枚举，便于类型安全
enum NotificationType {
  offer('offer'),
  wishlist('wishlist'),
  system('system'),
  message('message'),
  purchase('purchase'),
  priceDrop('price_drop');

  const NotificationType(this.value);
  final String value;

  static NotificationType? fromString(String value) {
    for (var type in NotificationType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// 通知构建器，用于创建不同类型的通知
class NotificationBuilder {
  String? _recipientId;
  String? _senderId;
  NotificationType? _type;
  String? _title;
  String? _message;
  String? _listingId;
  String? _offerId;
  final Map<String, dynamic> _metadata = {};

  NotificationBuilder setRecipient(String recipientId) {
    _recipientId = recipientId;
    return this;
  }

  NotificationBuilder setSender(String senderId) {
    _senderId = senderId;
    return this;
  }

  NotificationBuilder setType(NotificationType type) {
    _type = type;
    return this;
  }

  NotificationBuilder setTitle(String title) {
    _title = title;
    return this;
  }

  NotificationBuilder setMessage(String message) {
    _message = message;
    return this;
  }

  NotificationBuilder setListing(String listingId) {
    _listingId = listingId;
    return this;
  }

  NotificationBuilder setOffer(String offerId) {
    _offerId = offerId;
    return this;
  }

  NotificationBuilder addMetadata(String key, dynamic value) {
    _metadata[key] = value;
    return this;
  }

  NotificationBuilder setMetadata(Map<String, dynamic> metadata) {
    _metadata.clear();
    _metadata.addAll(metadata);
    return this;
  }

  /// 构建通知对象
  Map<String, dynamic> build() {
    if (_recipientId == null) {
      throw ArgumentError('Recipient ID is required');
    }
    if (_type == null) {
      throw ArgumentError('Notification type is required');
    }
    if (_title == null || _title!.isEmpty) {
      throw ArgumentError('Title is required');
    }
    if (_message == null || _message!.isEmpty) {
      throw ArgumentError('Message is required');
    }

    return {
      'recipient_id': _recipientId,
      'sender_id': _senderId,
      'type': _type!.value,
      'title': _title,
      'message': _message,
      'listing_id': _listingId,
      'offer_id': _offerId,
      'metadata': _metadata,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  /// 构建报价通知
  static NotificationBuilder offer({
    required String recipientId,
    required String senderId,
    required String listingId,
    required String listingTitle,
    required double offerAmount,
    String? buyerName,
    String? buyerPhone,
    String? message,
  }) {
    final displayName = buyerName ?? 'Someone';
    return NotificationBuilder()
        .setRecipient(recipientId)
        .setSender(senderId)
        .setType(NotificationType.offer)
        .setListing(listingId)
        .setTitle('New Offer Received')
        .setMessage(
            '$displayName made an offer of \$$offerAmount for your $listingTitle')
        .addMetadata('offer_amount', offerAmount)
        .addMetadata('buyer_name', displayName)
        .addMetadata('buyer_phone', buyerPhone)
        .addMetadata('buyer_message', message)
        .addMetadata('listing_title', listingTitle);
  }

  /// 构建收藏通知
  static NotificationBuilder wishlist({
    required String recipientId,
    required String senderId,
    required String listingId,
    required String listingTitle,
    String? likerName,
  }) {
    final displayName = likerName ?? 'Someone';
    return NotificationBuilder()
        .setRecipient(recipientId)
        .setSender(senderId)
        .setType(NotificationType.wishlist)
        .setListing(listingId)
        .setTitle('Item Added to Wishlist')
        .setMessage('$displayName added your $listingTitle to their wishlist')
        .addMetadata('liker_name', displayName)
        .addMetadata('listing_title', listingTitle);
  }

  /// 构建系统通知
  static NotificationBuilder system({
    required String recipientId,
    required String title,
    required String message,
    Map<String, dynamic>? metadata,
  }) {
    final builder = NotificationBuilder()
        .setRecipient(recipientId)
        .setType(NotificationType.system)
        .setTitle(title)
        .setMessage(message);

    if (metadata != null) {
      builder.setMetadata(metadata);
    }

    return builder;
  }
}
