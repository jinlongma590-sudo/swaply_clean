// lib/models/offer.dart
import 'package:flutter/foundation.dart';

/// 报价状态枚举
enum OfferStatus {
  pending('pending', 'Pending', 0xFFFF9800),
  accepted('accepted', 'Accepted', 0xFF4CAF50),
  declined('declined', 'Declined', 0xFFF44336),
  expired('expired', 'Expired', 0xFF9E9E9E),
  withdrawn('withdrawn', 'Withdrawn', 0xFF607D8B);

  const OfferStatus(this.value, this.displayText, this.color);

  final String value;
  final String displayText;
  final int color;

  static OfferStatus fromString(String value) {
    return OfferStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => OfferStatus.pending,
    );
  }
}

/// 报价模型类
class OfferModel {
  final String id;
  final String listingId;
  final String buyerId;
  final String sellerId;
  final double offerAmount;
  final double? originalPrice;
  final String? message;
  final String? responseMessage;
  final String? buyerPhone;
  final String buyerName;
  final OfferStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  // 关联数据
  final String? listingTitle;
  final String? listingPrice;
  final List<String>? listingImages;
  final String? listingCity;
  final String? buyerAvatar;
  final String? contactPhone;

  OfferModel({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    required this.offerAmount,
    this.originalPrice,
    this.message,
    this.responseMessage,
    this.buyerPhone,
    required this.buyerName,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.listingTitle,
    this.listingPrice,
    this.listingImages,
    this.listingCity,
    this.buyerAvatar,
    this.contactPhone,
  });

  /// 从 Map 创建 OfferModel
  factory OfferModel.fromMap(Map<String, dynamic> map) {
    try {
      // 处理关联的商品数据
      final listingsData = map['listings'] as Map<String, dynamic>?;
      final buyerProfileData = map['buyer_profiles'] as Map<String, dynamic>?;

      // 处理图片数据
      List<String>? images;
      if (listingsData != null && listingsData['images'] != null) {
        final imageData = listingsData['images'];
        if (imageData is List) {
          images = imageData.map((e) => e.toString()).toList();
        } else if (imageData is String) {
          images = [imageData];
        }
      }

      return OfferModel(
        id: map['id']?.toString() ?? '',
        listingId: map['listing_id']?.toString() ?? '',
        buyerId: map['buyer_id']?.toString() ?? '',
        sellerId: map['seller_id']?.toString() ?? '',
        offerAmount: (map['offer_amount'] as num?)?.toDouble() ?? 0.0,
        originalPrice: (map['original_price'] as num?)?.toDouble(),
        message: map['message']?.toString(),
        responseMessage: map['response_message']?.toString(),
        buyerPhone: map['buyer_phone']?.toString(),
        buyerName: map['buyer_name']?.toString() ?? 'Unknown',
        status: OfferStatus.fromString(map['status']?.toString() ?? 'pending'),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: map['updated_at'] != null
            ? DateTime.tryParse(map['updated_at'].toString())
            : null,
        expiresAt: map['expires_at'] != null
            ? DateTime.tryParse(map['expires_at'].toString())
            : null,
        listingTitle: listingsData?['title']?.toString(),
        listingPrice: listingsData?['price']?.toString(),
        listingImages: images,
        listingCity: listingsData?['city']?.toString(),
        buyerAvatar: buyerProfileData?['avatar_url']?.toString(),
        contactPhone: buyerProfileData?['phone']?.toString() ??
            map['buyer_phone']?.toString(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing OfferModel: $e');
        print('Map data: $map');
      }
      rethrow;
    }
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'listing_id': listingId,
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'offer_amount': offerAmount,
      'original_price': originalPrice,
      'message': message,
      'response_message': responseMessage,
      'buyer_phone': buyerPhone,
      'buyer_name': buyerName,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  /// 创建副本
  OfferModel copyWith({
    String? id,
    String? listingId,
    String? buyerId,
    String? sellerId,
    double? offerAmount,
    double? originalPrice,
    String? message,
    String? responseMessage,
    String? buyerPhone,
    String? buyerName,
    OfferStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    String? listingTitle,
    String? listingPrice,
    List<String>? listingImages,
    String? listingCity,
    String? buyerAvatar,
    String? contactPhone,
  }) {
    return OfferModel(
      id: id ?? this.id,
      listingId: listingId ?? this.listingId,
      buyerId: buyerId ?? this.buyerId,
      sellerId: sellerId ?? this.sellerId,
      offerAmount: offerAmount ?? this.offerAmount,
      originalPrice: originalPrice ?? this.originalPrice,
      message: message ?? this.message,
      responseMessage: responseMessage ?? this.responseMessage,
      buyerPhone: buyerPhone ?? this.buyerPhone,
      buyerName: buyerName ?? this.buyerName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      listingTitle: listingTitle ?? this.listingTitle,
      listingPrice: listingPrice ?? this.listingPrice,
      listingImages: listingImages ?? this.listingImages,
      listingCity: listingCity ?? this.listingCity,
      buyerAvatar: buyerAvatar ?? this.buyerAvatar,
      contactPhone: contactPhone ?? this.contactPhone,
    );
  }

  // 便捷的getter方法

  /// 买家显示名称
  String get buyerDisplayName =>
      buyerName.isEmpty ? 'Unknown Buyer' : buyerName;

  /// 格式化的报价金额
  String get formattedOfferAmount {
    if (offerAmount >= 1000000) {
      return '\$${(offerAmount / 1000000).toStringAsFixed(1)}M';
    } else if (offerAmount >= 1000) {
      return '\$${(offerAmount / 1000).toStringAsFixed(1)}K';
    } else {
      return '\$${offerAmount.toStringAsFixed(0)}';
    }
  }

  /// 格式化的原始价格
  String? get formattedOriginalPrice {
    if (originalPrice == null) return null;
    final price = originalPrice!;
    if (price >= 1000000) {
      return '\$${(price / 1000000).toStringAsFixed(1)}M';
    } else if (price >= 1000) {
      return '\$${(price / 1000).toStringAsFixed(1)}K';
    } else {
      return '\$${price.toStringAsFixed(0)}';
    }
  }

  /// 报价占原价的百分比
  double get offerPercentage {
    if (originalPrice == null || originalPrice! <= 0) return 100.0;
    return (offerAmount / originalPrice!) * 100;
  }

  /// 是否过期
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// 距离过期的时间描述
  String? get formattedTimeUntilExpiry {
    if (expiresAt == null) return null;

    final now = DateTime.now();
    if (now.isAfter(expiresAt!)) {
      return 'Expired';
    }

    final difference = expiresAt!.difference(now);

    if (difference.inDays > 0) {
      return 'Expires in ${difference.inDays} day${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'Expires in ${difference.inHours} hour${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return 'Expires in ${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'Expires soon';
    }
  }

  /// 格式化创建时间
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
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  /// 格式化更新时间
  String? get updatedTimeAgo {
    if (updatedAt == null) return null;

    final now = DateTime.now();
    final difference = now.difference(updatedAt!);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${updatedAt!.day}/${updatedAt!.month}/${updatedAt!.year}';
    }
  }

  /// 是否可以撤回（只有待处理且未过期的报价才能撤回）
  bool get canWithdraw => status == OfferStatus.pending && !isExpired;

  /// 是否可以接受或拒绝（只有待处理且未过期的报价）
  bool get canRespond => status == OfferStatus.pending && !isExpired;

  @override
  String toString() {
    return 'OfferModel(id: $id, listingId: $listingId, buyerName: $buyerName, offerAmount: $offerAmount, status: ${status.value}, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is OfferModel &&
        other.id == id &&
        other.listingId == listingId &&
        other.buyerId == buyerId &&
        other.sellerId == sellerId &&
        other.offerAmount == offerAmount &&
        other.status == status;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        listingId.hashCode ^
        buyerId.hashCode ^
        sellerId.hashCode ^
        offerAmount.hashCode ^
        status.hashCode;
  }
}

/// 报价统计模型
class OfferStats {
  final int sentOffers;
  final int receivedOffers;
  final int pendingSent;
  final int pendingReceived;
  final int accepted;
  final int declined;
  final int expired;
  final int withdrawn;

  OfferStats({
    this.sentOffers = 0,
    this.receivedOffers = 0,
    this.pendingSent = 0,
    this.pendingReceived = 0,
    this.accepted = 0,
    this.declined = 0,
    this.expired = 0,
    this.withdrawn = 0,
  });

  factory OfferStats.fromMap(Map<String, int> map) {
    return OfferStats(
      sentOffers: map['sent_offers'] ?? 0,
      receivedOffers: map['received_offers'] ?? 0,
      pendingSent: map['pending_sent'] ?? 0,
      pendingReceived: map['pending_received'] ?? 0,
      accepted: map['accepted'] ?? 0,
      declined: map['declined'] ?? 0,
      expired: map['expired'] ?? 0,
      withdrawn: map['withdrawn'] ?? 0,
    );
  }

  Map<String, int> toMap() {
    return {
      'sent_offers': sentOffers,
      'received_offers': receivedOffers,
      'pending_sent': pendingSent,
      'pending_received': pendingReceived,
      'accepted': accepted,
      'declined': declined,
      'expired': expired,
      'withdrawn': withdrawn,
    };
  }

  /// 总的活跃报价数
  int get totalActive => pendingSent + pendingReceived;

  /// 成功率（接受的报价占总发送报价的百分比）
  double get successRate {
    if (sentOffers == 0) return 0.0;
    return (accepted / sentOffers) * 100;
  }

  /// 响应率（已响应的报价占收到报价的百分比）
  double get responseRate {
    if (receivedOffers == 0) return 0.0;
    final responded = accepted + declined;
    return (responded / receivedOffers) * 100;
  }

  @override
  String toString() {
    return 'OfferStats(sent: $sentOffers, received: $receivedOffers, pending: $totalActive, success: ${successRate.toStringAsFixed(1)}%)';
  }
}
