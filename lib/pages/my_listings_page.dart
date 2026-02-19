// lib/pages/my_listings_page.dart
// ✅ [性能优化] 删除商品速度优化：先删数据库+立即更新UI+后台异步删图片

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:swaply/services/listing_service.dart';
import 'package:swaply/services/offer_service.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/message_service.dart';
import 'package:swaply/models/offer.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:flutter/foundation.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/utils/image_utils.dart'; // 图片优化工具

class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});
  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  List<Map<String, dynamic>> _listings = [];
  List<OfferModel> _receivedOffers = [];
  bool _isLoadingListings = true;
  bool _isLoadingOffers = true;
  String? _errorMessage;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..value = 1.0;
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadListings(),
      _loadReceivedOffers(),
    ]);
    _animationController.forward();
  }

  // 1. 缓存读写核心逻辑
  Future<void> _cacheMyListings(String userId, List<Map<String, dynamic>> products) async {
    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'my_listings_$userId';
    final String jsonString = jsonEncode(products);
    await prefs.setString(cacheKey, jsonString);
    if (kDebugMode) {
      print('[MyListings Cache] 已缓存 ${products.length} 条数据 for user: $userId');
    }
  }

  Future<List<Map<String, dynamic>>?> _getCachedMyListings(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'my_listings_$userId';
    final String? jsonString = prefs.getString(cacheKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        final cachedData = decodedList.cast<Map<String, dynamic>>().toList();
        if (kDebugMode) {
          print('[MyListings Cache] 从缓存读取 ${cachedData.length} 条数据 for user: $userId');
        }
        return cachedData;
      } catch (e) {
        if (kDebugMode) {
          print('[MyListings Cache] 缓存数据解析失败: $e');
        }
      }
    }
    return null;
  }

  Future<void> _loadListings() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (kDebugMode) {
        print('[MyListings] ERROR: No authenticated user');
      }
      setState(() {
        _isLoadingListings = false;
        _errorMessage = 'Please login to view your listings';
      });
      return;
    }

    final userId = user.id;
    
    // 2. 页面加载业务流 - 优先从缓存读取并瞬间渲染
    final cachedData = await _getCachedMyListings(userId);
    if (cachedData != null && cachedData.isNotEmpty) {
      if (kDebugMode) {
        print('[MyListings] 从缓存加载 ${cachedData.length} 条数据，立即渲染');
      }
      setState(() { 
        _listings = cachedData;
        _isLoadingListings = false;
      });
    } else {
      setState(() {
        _isLoadingListings = true;
        _errorMessage = null;
      });
    }

    // 后台静默请求网络更新
    try {
      if (kDebugMode) {
        print('[MyListings] 后台静默请求网络更新 for user: $userId');
      }

      final response = await Supabase.instance.client
          .from('listings')
          .select(
              'id, title, description, category, city, price, seller_name, phone, contact_phone, images, image_urls, created_at, views_count, status, is_active')
          .eq('user_id', userId)
          .neq('status', 'deleted')
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        final freshData = (response as List).map<Map<String, dynamic>>((item) {
          if (item is Map<String, dynamic>) {
            return item;
          } else if (item is Map) {
            return Map<String, dynamic>.from(item);
          } else {
            return <String, dynamic>{};
          }
        }).toList();
        
        setState(() {
          _listings = freshData;
          _isLoadingListings = false;
        });

        // 更新缓存
        await _cacheMyListings(userId, freshData);
        
        if (kDebugMode) {
          print('[MyListings] 网络更新完成，加载 ${freshData.length} 条数据，缓存已更新');
          final statusCounts = <String, int>{};
          for (final listing in freshData) {
            final status = listing['status'] ?? 'unknown';
            statusCounts[status] = (statusCounts[status] ?? 0) + 1;
          }
          print('[MyListings] Status distribution: $statusCounts');
        }
      }
    } catch (e) {
      // 断网降级处理：保留缓存 UI，给出轻量提示
      if (kDebugMode) {
        print('[MyListings] 网络请求失败，使用缓存数据: $e');
      }
      
      if (cachedData == null || cachedData.isEmpty) {
        // 如果没有缓存数据，显示错误信息
        if (mounted) {
          setState(() {
            _isLoadingListings = false;
            _errorMessage = 'Failed to load listings. Please check your connection.';
          });
        }
      } else {
        // 有缓存数据，显示离线模式提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offline mode: Showing cached listings'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<Map<String, int>> _getInquiryStats(String listingId) async {
    try {
      final response = await Supabase.instance.client
          .from('inquiries')
          .select('type')
          .eq('listing_id', listingId);

      final data = response as List;
      final stats = <String, int>{
        'total': data.length,
        'call': 0,
        'whatsapp': 0,
        'offer': 0,
      };

      for (var item in data) {
        final type = item['type']?.toString() ?? '';
        stats[type] = (stats[type] ?? 0) + 1;
      }

      return stats;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get inquiry stats: $e');
      }
      return {'total': 0, 'call': 0, 'whatsapp': 0, 'offer': 0};
    }
  }

  Future<void> _loadReceivedOffers() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoadingOffers = false);
      return;
    }

    try {
      setState(() => _isLoadingOffers = true);

      final offers = await OfferService.getReceivedOffers(
        userId: user.id,
        limit: 100,
      );

      List<Map<String, dynamic>> offersMutable = [];

      for (var offer in offers) {
        offersMutable.add(offer);
      }

      if (offersMutable.isEmpty) {
        try {
          final supa = Supabase.instance.client;
          final raw = await supa
              .from('offers')
              .select('*, listings!inner(id,title,images,price,city)')
              .eq('seller_id', user.id)
              .order('created_at', ascending: false);

          if (raw.isNotEmpty) {
            for (var item in raw) {
              offersMutable.add(item);
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _receivedOffers =
              offersMutable.map((offer) => OfferModel.fromMap(offer)).toList();
          _isLoadingOffers = false;
        });

        if (kDebugMode) {
          print('Loaded ${offersMutable.length} received offers');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading offers: $e');
      }

      if (mounted) {
        setState(() => _isLoadingOffers = false);
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadData();
  }

  // ✅ [性能优化] 删除逻辑优化：先删数据库 → UI立即响应 → 后台删图片
  Future<void> _deleteListing(Map<String, dynamic> listing, int index) async {
    try {
      // ✅ 验证 ID
      final listingId = listing['id']?.toString();
      if (listingId == null || listingId.isEmpty) {
        throw Exception('Invalid listing ID');
      }

      // ✅ 提取图片路径（用于后台删除）
      final images = ListingService.readImages(listing);
      final imagePaths = images
          .map(ListingService.publicUrlToObjectPath)
          .where((path) => path != null)
          .cast<String>()
          .toList();

      // ✅ 【优化1】先删数据库（快速）
      await Supabase.instance.client
          .from('listings')
          .delete()
          .eq('id', listingId);

      // ✅ 【优化2】立即更新UI（用户感知删除成功）
      if (mounted) {
        setState(() {
          _listings.removeAt(index);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 14.sp),
                SizedBox(width: 8.w),
                const Text('Listing deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r)),
            margin: EdgeInsets.all(12.w),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // ✅ 【优化3】后台异步删除图片（不阻塞UI）
      if (imagePaths.isNotEmpty) {
        _deleteImagesInBackground(imagePaths);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting listing: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 14.sp),
                SizedBox(width: 8.w),
                Expanded(
                    child: Text('Failed to delete listing: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      }
    }
  }

  /// ✅ [新增] 后台静默删除图片（失败不影响用户体验）
  void _deleteImagesInBackground(List<String> imagePaths) {
    Future.microtask(() async {
      try {
        await Supabase.instance.client.storage
            .from('listings')
            .remove(imagePaths);
        if (kDebugMode) {
          print('✅ Background: ${imagePaths.length} images deleted');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Background image deletion failed (non-critical): $e');
        }
        // 静默失败，不打扰用户
      }
    });
  }

  void _showDeleteDialog(Map<String, dynamic> listing, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6.r),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child:
                    Icon(Icons.delete_outline, color: Colors.red, size: 18.r),
              ),
              SizedBox(width: 10.w),
              Text('Delete Listing',
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
            ],
          ),
          content: Text(
            'Are you sure you want to delete "${listing['title'] ?? 'this listing'}"? This action cannot be undone.',
            style: TextStyle(fontSize: 14.sp, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(fontSize: 14.sp, color: Colors.grey[600])),
            ),
            Container(
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(6.r)),
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteListing(listing, index);
                },
                child: const Text('Delete',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleOfferAction(
      OfferModel offer, OfferStatus newStatus, String? message) async {
    try {
      final success = await OfferService.updateOfferStatus(
        offerId: offer.id,
        status: newStatus,
        responseMessage: message,
      );

      if (success) {
        await _loadReceivedOffers();

        if (newStatus == OfferStatus.accepted ||
            newStatus == OfferStatus.declined) {
          try {
            if (newStatus == OfferStatus.accepted) {
              await NotificationService.createSystemNotification(
                recipientId: offer.buyerId,
                title: 'Offer Accepted!',
                message:
                    'Your offer of ${offer.formattedOfferAmount} for ${offer.listingTitle ?? 'the item'} has been accepted!',
                metadata: {
                  'offer_amount': offer.offerAmount,
                  'listing_title': offer.listingTitle,
                  'action': newStatus.value,
                  'response_message': message,
                  'listing_id': offer.listingId,
                  'offer_id': offer.id,
                },
              );

              await MessageService.createSystemMessage(
                offerId: offer.id,
                receiverId: offer.buyerId,
                message: message != null && message.isNotEmpty
                    ? 'Offer accepted: $message'
                    : 'Your offer has been accepted!',
              );
            } else {
              await NotificationService.createSystemNotification(
                recipientId: offer.buyerId,
                title: 'Offer Declined',
                message:
                    'Your offer of ${offer.formattedOfferAmount} for ${offer.listingTitle ?? 'the item'} has been declined${message != null && message.isNotEmpty ? ': $message' : '.'}',
                metadata: {
                  'offer_amount': offer.offerAmount,
                  'listing_title': offer.listingTitle,
                  'action': newStatus.value,
                  'response_message': message,
                  'listing_id': offer.listingId,
                  'offer_id': offer.id,
                },
              );

              await MessageService.createSystemMessage(
                offerId: offer.id,
                receiverId: offer.buyerId,
                message: message != null && message.isNotEmpty
                    ? 'Offer declined: $message'
                    : 'Your offer has been declined.',
              );
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error sending notification or creating message: $e');
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 14.sp),
                  SizedBox(width: 8.w),
                  Text(
                      'Offer ${newStatus.displayText.toLowerCase()} successfully'),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r)),
              margin: EdgeInsets.all(12.w),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling offer action: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.white, size: 14.sp),
                SizedBox(width: 8.w),
                Expanded(
                    child: Text(
                        'Failed to ${newStatus.displayText.toLowerCase()} offer')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r)),
            margin: EdgeInsets.all(12.w),
          ),
        );
      }
    }
  }

  Color _getStatusColor(OfferStatus status) {
    switch (status) {
      case OfferStatus.pending:
        return Colors.orange;
      case OfferStatus.accepted:
        return Colors.green;
      case OfferStatus.declined:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (isIOS) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ));
    }
    final Widget tabBarWidget = Container(
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.7),
        indicator: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8.r),
        ),
        labelStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            TextStyle(fontSize: 12.sp, fontWeight: FontWeight.normal),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        tabs: [
          Tab(text: 'Items (${_listings.length})'),
          Tab(text: 'Offers (${_receivedOffers.length})'),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          _buildHeader(
            statusBar,
            isIOS,
            tabBarWidget,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListingsTab(),
                _buildOffersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    double statusBar,
    bool isIOS,
    Widget tabBarWidget,
  ) {
    if (isIOS) {
      const double kNavBarHeight = 44.0;
      const double kButtonSize = 32.0;
      const double kSidePadding = 16.0;
      const double kButtonSpacing = 12.0;

      const double kTabsH = 32.0;
      const double kTabsTop = 8.0;
      const double kTabsBottom = 12.0;

      final Widget iosBackButton = SizedBox(
        width: kButtonSize,
        height: kButtonSize,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: Colors.white),
          ),
        ),
      );

      final Widget iosTitle = Expanded(
        child: Text(
          'My Listings',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

      const Widget iosRightPlaceholder =
          SizedBox(width: kButtonSize, height: kButtonSize);

      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2563EB),
              Color(0xFF3B82F6),
              Color(0xFF60A5FA),
            ],
          ),
        ),
        padding: EdgeInsets.only(top: statusBar),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: kNavBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSidePadding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    iosBackButton,
                    const SizedBox(width: kButtonSpacing),
                    iosTitle,
                    const SizedBox(width: kButtonSpacing),
                    iosRightPlaceholder,
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(
                  kSidePadding, kTabsTop, kSidePadding, kTabsBottom),
              height: kTabsH,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: tabBarWidget,
            ),
          ],
        ),
      );
    }
    final Widget backButton = GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
    final Widget titleText = Text(
      'My Listings',
      style: TextStyle(
        color: Colors.white,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF60A5FA)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  backButton,
                  const SizedBox(width: 12),
                  Expanded(child: titleText),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: tabBarWidget,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListingsTab() {
    if (_isLoadingListings) {
      return _buildLoadingState('Loading your listings...');
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }
    if (_listings.isEmpty) {
      return _buildEmptyListingsState();
    }
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF2563EB),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ListView.builder(
          padding: EdgeInsets.all(12.w),
          itemCount: _listings.length,
          itemBuilder: (context, index) {
            return _buildListingCard(_listings[index], index);
          },
        ),
      ),
    );
  }

  Widget _buildOffersTab() {
    if (_isLoadingOffers) {
      return _buildLoadingState('Loading offers...');
    }

    if (_receivedOffers.isEmpty) {
      return _buildEmptyOffersState();
    }
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF2563EB),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ListView.builder(
          padding: EdgeInsets.all(12.w),
          itemCount: _receivedOffers.length,
          itemBuilder: (context, index) {
            return _buildOfferCard(_receivedOffers[index], index);
          },
        ),
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing, int index) {
    final title = listing['title']?.toString() ?? 'No Title';
    final price = listing['price']?.toString() ?? 'No Price';
    final images = ListingService.readImages(listing) ?? <String>[];
    final firstImage =
        images.isNotEmpty ? images.first : 'assets/images/placeholder.jpg';
    final city = listing['city']?.toString() ?? '';
    final createdAt = listing['created_at']?.toString() ?? '';
    final listingId = listing['id']?.toString() ?? '';
    final viewsCount = listing['views_count'] ?? 0;
    final status = listing['status']?.toString() ?? 'active';

    String timeAgo = 'Recently';
    if (createdAt.isNotEmpty) {
      try {
        final date = DateTime.parse(createdAt);
        final now = DateTime.now();
        final difference = now.difference(date);

        if (difference.inMinutes < 60) {
          timeAgo = '${difference.inMinutes}m ago';
        } else if (difference.inHours < 24) {
          timeAgo = '${difference.inHours}h ago';
        } else if (difference.inDays < 7) {
          timeAgo = '${difference.inDays}d ago';
        } else {
          timeAgo = '${date.day}/${date.month}/${date.year}';
        }
      } catch (e) {
        timeAgo = 'Recently';
      }
    }
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 200 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: EdgeInsets.only(bottom: 8.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8.r,
                    offset: Offset(0, 2.h),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50.w,
                          height: 50.h,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8.r),
                            color: Colors.grey.shade100,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                firstImage.startsWith('http')
                                    ? Image.network(
                                        SupabaseImageConfig.getThumbnailUrl(firstImage),
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Icon(Icons.image_rounded,
                                              color: Colors.grey.shade400,
                                              size: 20.w);
                                        },
                                      )
                                    : Image.asset(
                                        firstImage,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Icon(Icons.image_rounded,
                                              color: Colors.grey.shade400,
                                              size: 20.w);
                                        },
                                      ),
                                if (status == 'sold')
                                  Container(
                                    color: Colors.black45,
                                    child: Center(
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 6.w, vertical: 2.h),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(4.r),
                                        ),
                                        child: Text(
                                          'SOLD',
                                          style: TextStyle(
                                            fontSize: 8.sp,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                  color: status == 'sold' ? Colors.grey : Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                price,
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Row(
                                children: [
                                  if (city.isNotEmpty) ...[
                                    Icon(Icons.location_on_outlined,
                                        size: 12.w,
                                        color: Colors.grey.shade500),
                                    SizedBox(width: 2.w),
                                    Flexible(
                                      child: Text(
                                        city,
                                        style: TextStyle(
                                          fontSize: 11.sp,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 6.w),
                                  ],
                                  Icon(Icons.access_time,
                                      size: 11.w, color: Colors.grey.shade500),
                                  SizedBox(width: 2.w),
                                  Text(
                                    timeAgo,
                                    style: TextStyle(
                                        fontSize: 11.sp,
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: PopupMenuButton<String>(
                            onSelected: (value) async {
                              switch (value) {
                                case 'edit':
                                  SafeNavigator.push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SellFormPage(editingListing: listing),
                                    ),
                                  ).then((value) {
                                    if (value == true) {
                                      // 编辑成功，刷新列表
                                      _loadListings();
                                    }
                                  });
                                  break;
                                case 'update_status':
                                  final newStatus = status == 'active' ? 'sold' : 'active';
                                  try {
                                    await ListingService.updateListingStatus(
                                      listingId: listingId,
                                      newStatus: newStatus,
                                    );
                                    // 更新本地列表状态
                                    setState(() {
                                      listing['status'] = newStatus;
                                    });
                                    // 显示成功提示
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(newStatus == 'sold'
                                          ? 'Item marked as sold'
                                          : 'Item marked as available'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Status update failed: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                  break;
                                case 'delete':
                                  _showDeleteDialog(listing, index);
                                  break;
                              }
                            },
                            icon: Icon(Icons.more_horiz,
                                size: 20.r, color: Colors.grey.shade600),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.r)),
                            itemBuilder: (BuildContext context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined,
                                        size: 16.r,
                                        color: const Color(0xFF2563EB)),
                                    SizedBox(width: 8.w),
                                    const Text('Edit',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'update_status',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 16.r,
                                      color: status == 'active' ? Colors.green : Colors.blue,
                                    ),
                                    SizedBox(width: 8.w),
                                    Text(
                                      status == 'active' ? 'Mark as Sold' : 'Mark as Available',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: status == 'active' ? Colors.green : Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 16.r, color: Colors.red),
                                    SizedBox(width: 8.w),
                                    const Text('Delete',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(
                          color: const Color(0xFF2563EB).withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                SafeNavigator.push(
                                  MaterialPageRoute(
                                    builder: (context) => ProductDetailPage(
                                      productId: listing['id']?.toString(),
                                      productData: listing,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 4.h),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(6.r),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB)
                                            .withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(6.r),
                                      ),
                                      child: Icon(
                                        Icons.visibility_outlined,
                                        size: 14.r,
                                        color: const Color(0xFF2563EB),
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$viewsCount',
                                          style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF2563EB),
                                          ),
                                        ),
                                        Text(
                                          'Views',
                                          style: TextStyle(
                                            fontSize: 10.sp,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            height: 30.h,
                            width: 1.w,
                            color: const Color(0xFF2563EB).withOpacity(0.2),
                            margin: EdgeInsets.symmetric(horizontal: 8.w),
                          ),
                          Expanded(
                            child: FutureBuilder<Map<String, int>>(
                              future: _getInquiryStats(listingId),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Container(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 4.h),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(6.r),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.green.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(6.r),
                                          ),
                                          child: SizedBox(
                                            width: 14.r,
                                            height: 14.r,
                                            child:
                                                const CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.green),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 8.w),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('...',
                                                style: TextStyle(
                                                    fontSize: 14.sp,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Text('Inquiries',
                                                style: TextStyle(
                                                    fontSize: 10.sp,
                                                    color: Colors.grey[600])),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final stats = snapshot.data ??
                                    {
                                      'total': 0,
                                      'call': 0,
                                      'whatsapp': 0,
                                      'offer': 0
                                    };
                                final totalInquiries = stats['total'] ?? 0;

                                return GestureDetector(
                                  onTap: () {
                                    _showInquiryBreakdown(
                                        context, stats, title);
                                  },
                                  child: Container(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 4.h),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(6.r),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.green.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(6.r),
                                          ),
                                          child: Icon(
                                            Icons.chat_bubble_outline,
                                            size: 14.r,
                                            color: Colors.green,
                                          ),
                                        ),
                                        SizedBox(width: 8.w),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '$totalInquiries',
                                                style: TextStyle(
                                                  fontSize: 14.sp,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                              Text(
                                                'Inquiries',
                                                style: TextStyle(
                                                  fontSize: 10.sp,
                                                  color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (totalInquiries > 0)
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            size: 12.r,
                                            color: Colors.green,
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showInquiryBreakdown(
      BuildContext context, Map<String, int> stats, String title) {
    final calls = stats['call'] ?? 0;
    final whatsapp = stats['whatsapp'] ?? 0;
    final offers = stats['offer'] ?? 0;
    final total = stats['total'] ?? 0;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: EdgeInsets.all(16.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(6.r),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Icon(Icons.analytics_outlined,
                          color: Colors.green, size: 16.r),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        'Inquiry Breakdown',
                        style: TextStyle(
                            fontSize: 15.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                Text(
                  title,
                  style:
                      TextStyle(fontSize: 12.sp, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 12.h),
                _buildStatRow(Icons.phone, 'Phone Calls', calls, Colors.green),
                SizedBox(height: 8.h),
                _buildStatRow(
                    Icons.chat, 'WhatsApp', whatsapp, const Color(0xFF25D366)),
                SizedBox(height: 8.h),
                _buildStatRow(Icons.local_offer, 'Offers', offers,
                    const Color(0xFF2563EB)),
                SizedBox(height: 10.h),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                SizedBox(height: 10.h),
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Inquiries',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Text(
                        '$total',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                        ),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatRow(IconData icon, String label, int count, Color color) {
    return Container(
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.r),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Icon(icon, size: 14.r, color: color),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(OfferModel offer, int index) {
    final images = offer.listingImages ?? <String>[];
    final firstImage =
        images.isNotEmpty ? images.first : 'assets/images/placeholder.jpg';

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 200 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: EdgeInsets.only(bottom: 10.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: _getStatusColor(offer.status).withOpacity(0.08),
                    blurRadius: 8.r,
                    offset: Offset(0, 2.h),
                  ),
                ],
                border: Border.all(
                  color: _getStatusColor(offer.status).withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 45.w,
                          height: 45.h,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8.r),
                            color: Colors.grey.shade100,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: firstImage.startsWith('http')
                                ? Image.network(
                                    SupabaseImageConfig.getThumbnailUrl(firstImage),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(Icons.image_rounded,
                                          color: Colors.grey.shade400,
                                          size: 18.w);
                                    },
                                  )
                                : Image.asset(
                                    firstImage,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(Icons.image_rounded,
                                          color: Colors.grey.shade400,
                                          size: 18.w);
                                    },
                                  ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                offer.listingTitle ?? 'Unknown Item',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 3.h),
                              Row(
                                children: [
                                  Text(
                                    'Offer: ',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    offer.formattedOfferAmount,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                'From ${offer.buyerName ?? 'Unknown'}',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color:
                                _getStatusColor(offer.status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            offer.status.displayText,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(offer.status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (offer.status == OfferStatus.pending) ...[
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 32.h,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: ElevatedButton(
                                onPressed: () => _handleOfferAction(
                                    offer, OfferStatus.declined, null),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.grey.shade700,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.r)),
                                ),
                                child: Text('Decline',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.sp)),
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Container(
                              height: 32.h,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF2563EB),
                                    Color(0xFF3B82F6)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: ElevatedButton(
                                onPressed: () => _handleOfferAction(
                                    offer, OfferStatus.accepted, null),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.r)),
                                ),
                                child: Text('Accept',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.sp)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32.w,
              height: 32.h,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFF2563EB),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              message,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60.w,
              height: 60.h,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30.r),
              ),
              child: Icon(
                Icons.error_outline,
                size: 30.r,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              _errorMessage ?? 'Unable to load your listings',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: ElevatedButton(
                onPressed: _refreshData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 10.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r)),
                ),
                child: Text('Try Again',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyListingsState() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80.w,
              height: 80.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(40.r),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.3),
                    blurRadius: 12.r,
                    offset: Offset(0, 6.h),
                  ),
                ],
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 40.r,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'No listings yet',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Start selling by creating your first listing and reach thousands of buyers',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                ),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  SafeNavigator.push(
                    MaterialPageRoute(
                        builder: (context) => const SellFormPage()),
                  );
                },
                icon: Icon(Icons.add, color: Colors.white, size: 16.r),
                label: Text('Create Your First Listing',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                      EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyOffersState() {
    return Center(
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80.w,
              height: 80.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade400, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(40.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 12.r,
                    offset: Offset(0, 6.h),
                  ),
                ],
              ),
              child: Icon(
                Icons.local_offer_outlined,
                size: 40.r,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'No offers received',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'When buyers make offers on your items, they will appear here for you to accept or decline',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
