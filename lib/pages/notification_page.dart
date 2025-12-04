// lib/pages/notification_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:swaply/core/l10n/app_localizations.dart';
import 'package:swaply/router/root_nav.dart'; // navPush / navReplaceAll
import 'package:swaply/theme/constants.dart'; // kPrimaryBlue
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/offer_detail_cache.dart'; // 🚀 新增缓存预取

// ⬇️ 统一配置：Offer 详情页的路由名 —— 与 AppRouter 保持一致
const String _kOfferDetailRoute = '/offer-detail';

class NotificationPage extends StatefulWidget {
  final VoidCallback? onClearBadge;
  final bool isGuest;
  final Function(int)? onNotificationCountChanged;

  const NotificationPage({
    super.key,
    this.onClearBadge,
    this.isGuest = false,
    this.onNotificationCountChanged,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadNotifications();
      _subscribeToNotifications();
    } else {
      _isLoading = false;
    }

    // 清空角标（如果底栏需要）
    if (widget.onClearBadge != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClearBadge!());
    }
  }

  @override
  void dispose() {
    _unsubscribeFromNotifications();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      setState(() => _isLoading = true);

      final notifications = await NotificationService.getUserNotifications(
        limit: 100,
        includeRead: true,
      );

      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
      _updateUnreadCount();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _loadNotifications error: $e');
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _subscribeToNotifications() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await NotificationService.subscribeUser(
      user.id,
      onEvent: (Map<String, dynamic> notification) {
        if (!mounted) return;
        setState(() {
          _notifications.insert(0, notification);
        });
        _updateUnreadCount();
      },
    );
  }

  Future<void> _unsubscribeFromNotifications() async {
    await NotificationService.unsubscribe();
  }

  void _updateUnreadCount() {
    final unreadCount = _notifications.where((n) => n['is_read'] != true).length;
    widget.onNotificationCountChanged?.call(unreadCount);
  }

  Future<void> _markAsRead(int index) async {
    final notification = _notifications[index];
    if (notification['is_read'] == true) return;

    try {
      final success = await NotificationService.markNotificationAsRead(
        notification['id'].toString(),
      );

      if (success && mounted) {
        setState(() {
          _notifications[index]['is_read'] = true;
          _notifications[index]['read_at'] = DateTime.now().toIso8601String();
        });
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _markAsRead error: $e');
      }
    }
  }

  Future<void> _deleteNotification(int index) async {
    final l10n = AppLocalizations.of(context)!;
    final notification = _notifications[index];

    try {
      final success = await NotificationService.deleteNotification(
        notification['id'].toString(),
      );

      if (success && mounted) {
        setState(() => _notifications.removeAt(index));
        _updateUnreadCount();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 14.sp),
                SizedBox(width: 6.w),
                Text(l10n.notificationDeleted, style: TextStyle(fontSize: 12.sp)),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
            margin: EdgeInsets.all(8.w),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _deleteNotification error: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 14.sp),
              SizedBox(width: 6.w),
              const Expanded(child: Text('Failed to delete notification')),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
          margin: EdgeInsets.all(8.w),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final success = await NotificationService.markAllNotificationsAsRead();

      if (success && mounted) {
        setState(() {
          for (var n in _notifications) {
            n['is_read'] = true;
            n['read_at'] = DateTime.now().toIso8601String();
          }
        });
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _markAllAsRead error: $e');
      }
    }
  }

  Future<void> _clearAll() async {
    try {
      final success = await NotificationService.clearAllNotifications();

      if (success && mounted) {
        setState(() => _notifications.clear());
        _updateUnreadCount();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notifications] _clearAll error: $e');
      }
    }
  }

  Widget _getNotificationIcon(String type) {
    final color = Color(NotificationService.getNotificationColor(type));
    IconData iconData;

    switch (type) {
      case 'offer':
        iconData = Icons.local_offer_rounded;
        break;
      case 'wishlist':
        iconData = Icons.bookmark_rounded;
        break;
      case 'purchase':
        iconData = Icons.shopping_cart_rounded;
        break;
      case 'message':
        iconData = Icons.message_rounded;
        break;
      case 'price_drop':
        iconData = Icons.trending_down_rounded;
        break;
      case 'system':
      default:
        iconData = Icons.notifications_rounded;
    }

    return Container(
      width: 32.w,
      height: 32.w,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Icon(iconData, color: color, size: 16.r),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontSize: 12.sp)),
        backgroundColor: isError ? Colors.red.shade600 : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
        margin: EdgeInsets.all(8.w),
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  // ⬇️ 统一从 notification / payload / metadata 取 ID
  String? _getId(Map<String, dynamic> n, String key) {
    // 顶层
    final v = n[key];
    if (v != null && v.toString().isNotEmpty) return v.toString();

    // payload
    final payload = n['payload'];
    if (payload is Map) {
      final pv = payload[key];
      if (pv != null && pv.toString().isNotEmpty) return pv.toString();
    }

    // metadata
    final meta = n['metadata'];
    if (meta is Map) {
      final mv = meta[key];
      if (mv != null && mv.toString().isNotEmpty) return mv.toString();
    }
    return null;
  }

  bool _isOfferType(String t) {
    // 兼容你后台可能的不同命名
    switch (t) {
      case 'offer':
      case 'offer.new':
      case 'offer_counter':
      case 'offer.counter':
      case 'offer.accepted':
      case 'offer.rejected':
      case 'offer.canceled':
      case 'make_offer':
      case 'new_offer':
        return true;
      default:
        return false;
    }
  }

  // 🚀 优化后的点击处理：添加预取功能
  void _handleNotificationTap(Map<String, dynamic> notification) async {
    final index = _notifications.indexOf(notification);
    if (index >= 0) {
      _markAsRead(index);
    }

    final type = notification['type']?.toString() ?? '';

    // 统一解析 ID
    String? listingId = _getId(notification, 'listing_id');
    String? offerId   = _getId(notification, 'offer_id');

    if (type.isEmpty) {
      _showSnack('Notification data is incomplete', isError: true);
      return;
    }

    // ① 先处理所有"offer 系列"
    if (_isOfferType(type)) {
      if (offerId != null && offerId.isNotEmpty) {
        // 🚀 关键优化：先预取数据（不阻塞导航）
        OfferDetailCache.prefetch(offerId);

        await navPush(_kOfferDetailRoute, arguments: {'offerId': offerId});
        return;
      }
      if (listingId != null && listingId.isNotEmpty) {
        await navPush('/listing', arguments: listingId); // 兜底：至少打开商品
        return;
      }
      _showSnack('Cannot open offer: missing offer ID', isError: true);
      return;
    }

    // ② message：优先 offerId（有些"新出价"在你这边被标成 message）
    switch (type) {
      case 'message':
        if (offerId != null && offerId.isNotEmpty) {
          // 🚀 预取 offer 数据
          OfferDetailCache.prefetch(offerId);

          await navPush(_kOfferDetailRoute, arguments: {'offerId': offerId});
          return;
        }
        if (listingId != null && listingId.isNotEmpty) {
          await navPush('/listing', arguments: listingId);
        } else {
          _showSnack('Cannot open message: missing listing ID or offer ID',
              isError: true);
        }
        break;

      case 'system':
        if (listingId != null && listingId.isNotEmpty) {
          await navPush('/listing', arguments: listingId);
        } else {
          _showSnack('Cannot open notification: missing listing ID', isError: true);
        }
        break;

      case 'wishlist':
      case 'price_drop':
      default:
        if (listingId != null && listingId.isNotEmpty) {
          await navPush('/listing', arguments: listingId);
        } else {
          _showSnack('Cannot open notification: missing listing ID', isError: true);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // ✅ 统一与 WishlistPage / SellFormPage 一致的顶部逻辑
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (widget.isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: kPrimaryBlue,
          // ✅ 统一高度逻辑
          toolbarHeight: isIOS ? 44 : null,
          title: Text(
            l10n.notifications,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp, // ✅ 统一字体
              fontWeight: FontWeight.w600,
            ),
          ),
          elevation: 0,
          automaticallyImplyLeading: false, // ❌ 移除返回按钮
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60.w,
                height: 60.w,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(30.r),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 30.r,
                  color: Colors.grey.shade500,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                l10n.loginRequired,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 6.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Text(
                  l10n.loginToReceiveNotifications,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryBlue, const Color(0xFF1E88E5)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryBlue.withOpacity(0.3),
                      blurRadius: 8.r,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await navReplaceAll('/welcome'); // 统一路由
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  icon: Icon(Icons.login_rounded, size: 14.r, color: Colors.white),
                  label: Text(
                    l10n.loginNow,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 计算标题显示
    final unreadCount = _notifications.where((n) => n['is_read'] != true).length;
    final displayTitle = '${l10n.notifications}${unreadCount > 0 ? ' ($unreadCount)' : ''}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // ✅ 使用标准的 AppBar
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        toolbarHeight: isIOS ? 44 : null, // ✅ 统一高度逻辑
        elevation: 0,
        automaticallyImplyLeading: false, // ❌ 移除返回按钮
        title: Text(
          displayTitle,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp, // ✅ 统一字体大小
            fontWeight: FontWeight.w600, // ✅ 统一字重
          ),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: 6.w),
              child: PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20.r),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
                elevation: 6,
                onSelected: (value) {
                  if (value == 'mark_all_read') {
                    _markAllAsRead();
                  } else if (value == 'clear_all') {
                    _clearAll();
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem(
                    value: 'mark_all_read',
                    height: 36.h,
                    child: Row(
                      children: [
                        Icon(Icons.done_all_rounded,
                            size: 16.r, color: Colors.grey.shade700),
                        SizedBox(width: 8.w),
                        Text(l10n.markAllAsRead, style: TextStyle(fontSize: 12.sp)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear_all',
                    height: 36.h,
                    child: Row(
                      children: [
                        Icon(Icons.clear_all_rounded,
                            color: Colors.red, size: 16.r),
                        SizedBox(width: 8.w),
                        Text(
                          l10n.clearAll,
                          style: TextStyle(fontSize: 12.sp, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: kPrimaryBlue.withOpacity(0.08),
                blurRadius: 10.r,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryBlue.withOpacity(0.2),
                      kPrimaryBlue.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Center(
                  child: SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kPrimaryBlue),
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                'Loading notifications...',
                style: TextStyle(
                  color: kPrimaryBlue,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      )
          : _notifications.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kPrimaryBlue.withOpacity(0.1),
                    const Color(0xFF1E88E5).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30.r),
                border: Border.all(
                  color: kPrimaryBlue.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 30.r,
                color: kPrimaryBlue,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              l10n.noNotifications,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text(
                l10n.notificationsWillAppearHere,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12.sp,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadNotifications,
        color: kPrimaryBlue,
        backgroundColor: Colors.white,
        strokeWidth: 2.w,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _notifications.length,
          itemBuilder: (context, index) {
            final notification = _notifications[index];
            final isRead = notification['is_read'] == true;
            final type = notification['type']?.toString() ?? '';
            final createdAt = notification['created_at']?.toString() ?? '';

            return Dismissible(
              key: Key('${notification['id']}'),
              background: Container(
                color: Colors.red.shade600,
                alignment: Alignment.centerRight,
                padding: EdgeInsets.only(right: 12.w),
                child: Icon(Icons.delete_rounded, color: Colors.white, size: 20.r),
              ),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) => _deleteNotification(index),
              child: Container(
                color: isRead ? Colors.white : kPrimaryBlue.withOpacity(0.03),
                margin: EdgeInsets.only(bottom: 0.5.h),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _handleNotificationTap(notification),
                    splashColor: kPrimaryBlue.withOpacity(0.1),
                    highlightColor: kPrimaryBlue.withOpacity(0.05),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _getNotificationIcon(type),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${notification['title'] ?? ''}',
                                        style: TextStyle(
                                          fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                                          fontSize: 13.sp,
                                          color: Colors.black87,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 6.w,
                                        height: 6.w,
                                        margin: EdgeInsets.only(left: 6.w),
                                        decoration: const BoxDecoration(
                                          color: kPrimaryBlue,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  '${notification['message'] ?? ''}',
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 4.h),
                                Row(
                                  children: [
                                    Icon(Icons.access_time_rounded,
                                        size: 10.r, color: Colors.grey.shade400),
                                    SizedBox(width: 2.w),
                                    Text(
                                      NotificationService.formatNotificationTime(createdAt),
                                      style: TextStyle(
                                        fontSize: 10.sp,
                                        color: Colors.grey.shade400,
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
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    return child;
  }
}

const _kPrivacyUrl = 'https://www.swaply.cc/privacy';
const _kDeleteUrl = 'https://www.swaply.cc/delete-account';