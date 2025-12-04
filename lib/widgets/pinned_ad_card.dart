// lib/widgets/pinned_ad_card.dart
import 'package:flutter/material.dart';
import 'dart:io';

class PinnedAdCard extends StatelessWidget {
  final Map<String, dynamic> listingData;
  final Map<String, dynamic> pinnedData;
  final VoidCallback? onTap;
  final bool showPinnedBadge;

  const PinnedAdCard({
    super.key,
    required this.listingData,
    required this.pinnedData,
    this.onTap,
    this.showPinnedBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final images = _getImages();
    final title = listingData['title']?.toString() ?? '';
    final price = _formatPrice(listingData['price']);
    final city = listingData['city']?.toString() ?? '';
    // 改为兼容新旧字段：优先 expires_at，后备 pinned_until
    final pinnedUntil = _tryParseDate(
      pinnedData['expires_at'] ?? pinnedData['pinned_until'],
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.orange[300]!,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withAlpha(30),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片区域 + 置顶标识
            Expanded(
              child: Stack(
                children: [
                  // 主图片
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: SizedBox.expand(
                      child: _buildImage(images),
                    ),
                  ),

                  // 置顶标识
                  if (showPinnedBadge)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(30),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 12,
                              color: Colors.white,
                            ),
                            SizedBox(width: 2),
                            Text(
                              'PINNED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 渐变覆盖层（增强置顶效果）
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.orange.withAlpha(40),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 到期时间显示（右上角）
                  if (pinnedUntil != null && showPinnedBadge)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formatTimeUntilExpiry(pinnedUntil),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 信息区域
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border(
                  top: BorderSide(color: Colors.orange[100]!, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 价格
                  Text(
                    price,
                    style: const TextStyle(
                      color: Color(0xFF13C45B),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // 标题
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // 位置
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),

                      // 置顶剩余时间提示
                      if (pinnedUntil != null && showPinnedBadge)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.orange[200]!, width: 0.5),
                          ),
                          child: Text(
                            _formatRemainingDays(pinnedUntil),
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getImages() {
    final images = listingData['images'];
    if (images is List) {
      return images.map((e) => e.toString()).toList();
    }
    return [];
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'Price on request';

    if (price is num) {
      return '\$${price.toStringAsFixed(0)}';
    }

    final priceStr = price.toString();
    if (priceStr.isEmpty || priceStr == '0') {
      return 'Price on request';
    }

    // 如果已经包含货币符号，直接返回
    if (priceStr.contains('\$') || priceStr.contains('USD')) {
      return priceStr;
    }

    // 尝试解析数字
    final numPrice = num.tryParse(priceStr.replaceAll(RegExp(r'[^\d.]'), ''));
    if (numPrice != null) {
      return '\${numPrice.toStringAsFixed(0)}';
    }

    return priceStr;
  }

  Widget _buildImage(List<String> images) {
    if (images.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.image, size: 50, color: Colors.grey),
        ),
      );
    }

    final imageUrl = images.first;

    // 网络图片
    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    // 本地文件
    if (imageUrl.startsWith('/') || imageUrl.startsWith('file:')) {
      return Image.file(
        File(imageUrl.replaceFirst('file://', '')),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }

    // Assets 图片
    return Image.asset(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.image, size: 50, color: Colors.grey),
      ),
    );
  }

  String _formatTimeUntilExpiry(DateTime pinnedUntil) {
    final now = DateTime.now();
    if (now.isAfter(pinnedUntil)) {
      return 'Expired';
    }

    final difference = pinnedUntil.difference(now);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else {
      return '${difference.inMinutes}m';
    }
  }

  String _formatRemainingDays(DateTime pinnedUntil) {
    final now = DateTime.now();
    if (now.isAfter(pinnedUntil)) {
      return 'Expired';
    }

    final difference = pinnedUntil.difference(now);

    if (difference.inDays > 0) {
      return '${difference.inDays} days left';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h left';
    } else {
      return 'Expiring soon';
    }
  }

  // 兼容 DateTime/字符串 的安全解析
  DateTime? _tryParseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
