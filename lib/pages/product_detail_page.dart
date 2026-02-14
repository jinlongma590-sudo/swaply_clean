// lib/pages/product_detail_page.dart
// ✅ [iOS Deep Link 修复] 智能返回逻辑 - 根据登录状态决定返回目标
// ✅ [性能优化] 图片预加载 + 渐进式加载 + 智能缓存
// ✅ [UI修复] 修复分享弹窗锯齿问题
// ✅ [收藏优化] 乐观更新策略 - 立即响应用户操作，后台同步数据
// ✅ [Offer消息修复] 发送offer时同时发送消息到MessageService
// ✅ [发布奖励] 发布后自动弹窗展示奖励
// 修复：① 图片查看器黑屏 ② 深链接拉起优化 ③ 返回按钮智能处理 ④ 图片加载优化 ⑤ 分享弹窗锯齿 ⑥ 收藏速度优化 ⑦ Offer消息功能 ⑧ 发布奖励弹窗
// 严格遵守架构：不破坏 AuthFlowObserver/DeepLinkService/AppRouter 三层分离

import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/edge_functions_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';

import 'package:swaply/models/listing_store.dart';
import 'package:swaply/models/verification_types.dart' as vt;
import 'package:swaply/services/dual_favorites_service.dart';
import 'package:swaply/services/notification_service.dart';
import 'package:swaply/services/offer_service.dart';
import 'package:swaply/services/message_service.dart';
import 'package:swaply/core/qa_keys.dart';
import 'package:swaply/services/favorites_update_service.dart';
import 'package:swaply/pages/seller_profile_page.dart';
import 'package:swaply/services/verification_guard.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/widgets/verified_avatar.dart';
import 'package:swaply/utils/share_utils.dart';
import 'package:swaply/services/email_verification_service.dart';
import 'package:swaply/router/root_nav.dart';
import 'package:swaply/rewards/reward_bottom_sheet.dart';
import 'package:swaply/services/reward_after_publish.dart';
import 'package:swaply/core/qa_keys.dart'; // QaKeys
import 'package:swaply/utils/image_utils.dart'; // 图片优化工具

class ProductDetailPage extends StatefulWidget {
  final String? productId;
  final Map<String, dynamic>? productData;

  const ProductDetailPage({
    super.key,
    this.productId,
    this.productData,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage>
    with TickerProviderStateMixin {
  static const Color _primaryBlue = Color(0xFF1877F2);
  static const Color _successGreen = Color(0xFF4CAF50);
  static const double _topIconSize = 32;
  static const BoxConstraints _topIconConstraints =
      BoxConstraints(minWidth: 56, minHeight: 56);

  late PageController _pageController;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  int _currentImageIndex = 0;
  bool _isInFavorites = false;
  bool _isFavoritesLoading = false;
  bool _isOfferLoading = false;
  bool _loadingSeller = true;
  bool _isViewerOpening = false;

  Map<String, dynamic> product = {};
  List<String> productImages = [];
  Map<String, dynamic>? sellerInfo;

  bool _sellerVerified = false;
  Map<String, dynamic>? _sellerVerifyRow;
  vt.VerificationBadgeType _sellerBadge = vt.VerificationBadgeType.none;

  String? _sellerId;
  BlockStatus _blockStatus =
      const BlockStatus(iBlockedOther: false, otherBlockedMe: false);
  bool _loadingBlock = false;

  final _uuid = const Uuid();

  final Set<int> _precachedIndices = {};

  // ✅ [发布奖励] 防止重复弹窗
  bool _rewardShownOnce = false;

  // ✅ [发布奖励] 避免"第一次拿不到id导致漏弹"
  bool _rewardCheckQueued = false;

  void _queueRewardCheck() {
    if (_rewardShownOnce || _rewardCheckQueued) return;

    final listingId = widget.productId ?? product['id']?.toString();
    if (listingId == null || listingId.isEmpty) return;

    _rewardCheckQueued = true;

    // 下一帧再检查：不抢首帧、不和 build 抢 context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rewardCheckQueued = false;
      if (!mounted) return;
      unawaited(_maybeShowRewardAfterPublish());
    });
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, .30),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _prepareProductData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _incrementViewsWithRPC();
      _animationController.forward();
      _precacheAllImages();

      // ✅ [发布奖励] 页面渲染后再触发，不抢首帧
      if (mounted) {
        _maybeShowRewardAfterPublish();
      }
    });

    _hydrateListingFromCloudIfNeeded();

    // ✅ [改动 3] 删掉重复的 hydrate 调用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _checkFavoritesStatus();
        _loadSellerInfo();
        _loadSellerVerification();
      });
    });
  }

  // ✅ [发布奖励] 检查并显示奖励弹窗
  Future<void> _maybeShowRewardAfterPublish() async {
    debugPrint('[RewardDebug] _maybeShowRewardAfterPublish called');
    
    if (_rewardShownOnce) {
      debugPrint('[RewardDebug] Already shown once, returning');
      return;
    }

    final listingId = widget.productId ?? product['id']?.toString();
    if (listingId == null || listingId.isEmpty) {
      debugPrint('[RewardDebug] No listingId found, returning');
      debugPrint('[RewardDebug] widget.productId: ${widget.productId}');
      debugPrint('[RewardDebug] product[id]: ${product['id']}');
      return;
    }

    debugPrint('[RewardDebug] Listing ID: $listingId');
    
    // ✅ 只触发一次：消费 pending
    final should = RewardAfterPublish.I.consumeIfPending(listingId);
    debugPrint('[RewardDebug] consumeIfPending returned: $should');
    
    if (!should) {
      debugPrint('[RewardDebug] Not pending or already consumed, returning');
      return;
    }

    _rewardShownOnce = true;
    debugPrint('[RewardDebug] Marking as shown, starting reward flow');

    // ✅ 不 await，别阻塞 UI
    unawaited(_runRewardFlow(listingId));
  }

  // ✅ [发布奖励] 执行奖励流程
  Future<void> _runRewardFlow(String listingId) async {
    try {
      // 添加调试日志
      debugPrint('[RewardDebug] ==================== START ====================');
      debugPrint('[RewardDebug] Fetching reward for listing: $listingId');
      debugPrint('[RewardDebug] Current user: ${Supabase.instance.client.auth.currentUser?.id}');
      
      // 检查 pending 状态
      debugPrint('[RewardDebug] Pending contains $listingId: ${RewardAfterPublish.I.isPending(listingId)}');
      debugPrint('[RewardDebug] Consumed contains $listingId: ${RewardAfterPublish.I.isConsumed(listingId)}');
      debugPrint('[RewardDebug] All pending: ${RewardAfterPublish.I.pendingSet}');
      debugPrint('[RewardDebug] All consumed: ${RewardAfterPublish.I.consumedSet}');
      
      final data = await RewardAfterPublish.I.fetchReward(listingId);
      
      debugPrint('[RewardDebug] Edge Function response:');
      debugPrint('[RewardDebug]   ok: ${data['ok']}');
      debugPrint('[RewardDebug]   reason: ${data['reason']}');
      debugPrint('[RewardDebug]   detail: ${data['detail']}');
      debugPrint('[RewardDebug]   spins: ${data['spins']}');
      debugPrint('[RewardDebug]   auto_reveal: ${data['auto_reveal']}');
      debugPrint('[RewardDebug]   request_id: ${data['request_id']}');
      debugPrint('[RewardDebug]   full response: $data');
      
      if (!mounted) {
        debugPrint('[RewardDebug] Widget not mounted, returning');
        debugPrint('[RewardDebug] ==================== END (NOT MOUNTED) ====================');
        return;
      }

      // 你 edge function 返回 {ok:true,...}，这里防御一下
      if (data['ok'] != true) {
        debugPrint('[RewardDebug] Reward not ok, reason: ${data['reason']}');
        
        // 特殊处理：设备被阻止的情况，仍显示一个信息弹窗
        if (data['reason'] == 'device_blocked') {
          debugPrint('[RewardDebug] Device blocked, creating informative response');
          
          // 创建一个模拟的成功响应，显示设备限制信息
          final simulatedData = {
            'ok': true,
            'qualified_count': 1,
            'airtime_points': 0,
            'spins': 0,
            'milestone_progress_text': 'Device limit reached',
            'milestone_steps': [1, 5, 10, 20, 30],
            'milestone_spins_each': 1,
            'spin_granted_now': false,
            'spins_added_now': 0,
            'spin_grant_trigger_n': 0,
            'device_blocked': true,
            'blocked_message': data['message'] ?? 'Device already claimed first-listing reward',
          };
          
          debugPrint('[RewardDebug] Showing device blocked info bottom sheet');
          
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            useRootNavigator: true,
            useSafeArea: true,
            builder: (_) => RewardBottomSheet(
              data: simulatedData,
              campaignCode: 'launch_v1',
              listingId: listingId,
            ),
          );
          
          debugPrint('[RewardDebug] ==================== END (DEVICE BLOCKED INFO) ====================');
          return;
        }
        
        debugPrint('[RewardDebug] ==================== END (NOT OK) ====================');
        return;
      }

      debugPrint('[RewardDebug] Showing reward bottom sheet');
      
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (_) => RewardBottomSheet(
          data: data,
          campaignCode: 'launch_v1',
          listingId: listingId,
        ),
      );
      
      debugPrint('[RewardDebug] ==================== END (SUCCESS) ====================');
    } catch (e) {
      debugPrint('[RewardDebug] ERROR in reward flow: $e');
      debugPrint('[RewardDebug] Stack trace: ${e.toString()}');
      debugPrint('[RewardDebug] ==================== END (ERROR) ====================');
      // 生产环境建议只 log，不要弹错误奖励
      if (kDebugMode) {
        debugPrint('[RewardAfterPublish] error: $e');
      }
    }
  }

  void _precacheAllImages() {
    if (productImages.isEmpty || !mounted) return;

    for (int i = 0; i < productImages.length; i++) {
      final imageUrl = productImages[i];
      if (imageUrl.startsWith('http')) {
        precacheImage(
          NetworkImage(imageUrl),
          context,
          onError: (exception, stackTrace) {
            if (kDebugMode) {
              print('❌ Failed to precache image $i: $exception');
            }
          },
        );
      }
    }

    if (kDebugMode) {
      print('✅ Precaching ${productImages.length} product images');
    }
  }

  void _precacheAdjacentImages(int currentIndex) {
    if (!mounted) return;

    final indicesToCache = <int>[
      if (currentIndex > 0) currentIndex - 1,
      if (currentIndex < productImages.length - 1) currentIndex + 1,
    ];

    for (final index in indicesToCache) {
      if (_precachedIndices.contains(index)) continue;

      final imageUrl = productImages[index];
      if (imageUrl.startsWith('http')) {
        precacheImage(NetworkImage(imageUrl), context);
        _precachedIndices.add(index);

        if (kDebugMode) {
          print('🖼️ Precaching adjacent image $index');
        }
      }
    }
  }

  void _handleBack() {
    if (kDebugMode) {
      debugPrint('[ProductDetail] 🔙 Back button pressed');
      debugPrint('[ProductDetail] 🔍 canPop = ${Navigator.canPop(context)}');
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      if (kDebugMode) {
        debugPrint('[ProductDetail] ✅ Popped to previous page');
      }
    } else {
      final hasSession = Supabase.instance.client.auth.currentSession != null;

      if (kDebugMode) {
        debugPrint('[ProductDetail] 🏠 Cannot pop (likely deep link entry)');
        debugPrint('[ProductDetail] 🔐 Session exists: $hasSession');
      }

      if (hasSession) {
        if (kDebugMode) {
          debugPrint('[ProductDetail] 📱 Logged in, navigating to /home');
        }
        navReplaceAll('/home');
      } else {
        if (kDebugMode) {
          debugPrint(
              '[ProductDetail] 👋 Not logged in, navigating to /welcome');
        }
        navReplaceAll('/welcome');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    try {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null) {
        String? idFromArgs;
        Map<String, dynamic>? dataFromArgs;

        if (args is Map) {
          final map = Map<String, dynamic>.from(args.cast<dynamic, dynamic>());
          idFromArgs = (map['id'] ??
                  map['listing_id'] ??
                  map['listingId'] ??
                  (map['listing']?['id']) ??
                  (map['data']?['id']))
              ?.toString();
          dataFromArgs = map['data'] is Map
              ? Map<String, dynamic>.from((map['data']))
              : map;
        } else if (args is String) {
          idFromArgs = args;
        }

        bool needSet = false;

        if (idFromArgs != null && (product['id'] == null)) {
          product['id'] = idFromArgs;
          needSet = true;
        }
        if (dataFromArgs != null) {
          dataFromArgs.forEach((k, v) {
            if (product[k] == null && v != null) {
              product[k] = v;
              needSet = true;
            }
          });
          if (productImages.isEmpty && dataFromArgs['images'] is List) {
            productImages = (dataFromArgs['images'] as List)
                .map((e) => e.toString())
                .toList();
            needSet = true;
          }
        }

        if (needSet && mounted) setState(() {});
        // ✅ [改动 2.2] 参数/数据补齐后再试一次
        _queueRewardCheck();
        _hydrateListingFromCloudIfNeeded();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadSellerInfo() async {
    try {
      final sellerId = product['user_id'] ?? product['seller_id'];
      _sellerId = sellerId?.toString();

      if (sellerId == null) {
        if (kDebugMode) {
          print('⚠️ 无法加载卖家信息：sellerId 为空');
          print('当前商品数据: $product');
        }
        setState(() => _loadingSeller = false);
        return;
      }

      if (kDebugMode) print('🔍 正在加载卖家信息，sellerId: $sellerId');

      final profile = await Supabase.instance.client
          .from('public_profiles')
          .select('id, full_name, avatar_url, created_at')
          .eq('id', sellerId)
          .maybeSingle();

      if (kDebugMode) print('📊 从数据库获取的卖家资料: $profile');

      if (mounted && profile != null) {
        setState(() {
          sellerInfo = profile;
          _sellerVerified = false;
          _sellerBadge = vt.VerificationBadgeType.none;
          _loadingSeller = false;
        });

        _fetchBlockStatus();
        await _loadSellerVerification();
      } else {
        if (kDebugMode) print('⚠️ 未找到卖家资料');
        setState(() => _loadingSeller = false);
      }
    } catch (e) {
      if (kDebugMode) print('❌ 加载卖家信息失败: $e');
      if (mounted) setState(() => _loadingSeller = false);
    }
  }

  Future<void> _loadSellerVerification() async {
    final sellerId =
        _sellerId ?? (product['user_id'] ?? product['seller_id'])?.toString();

    if (sellerId == null || sellerId.isEmpty) return;

    try {
      final row =
          await EmailVerificationService().fetchPublicVerification(sellerId);

      if (kDebugMode) print('[ProductDetail] public verify row = $row');

      final badge = vt.VerificationBadgeUtil.getVerificationTypeFromUser(row);

      if (!mounted) return;
      setState(() {
        _sellerVerifyRow = row;
        _sellerBadge = badge;
        _sellerVerified = (badge != vt.VerificationBadgeType.none);
      });
    } catch (e) {
      if (kDebugMode) {
        print('[ProductDetail] fetchPublicVerification error: $e');
      }
    }
  }

  Future<void> _fetchBlockStatus() async {
    if (_sellerId == null) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;

    setState(() => _loadingBlock = true);
    final s = await OfferService.getBlockStatusBetween(a: me, b: _sellerId!);
    if (!mounted) return;
    setState(() {
      _blockStatus = s;
      _loadingBlock = false;
    });
  }

  void _navigateToSellerProfile() {
    final sellerId =
        sellerInfo?['id'] ?? product['user_id'] ?? product['seller_id'];

    if (sellerId != null) {
      SafeNavigator.push(
        MaterialPageRoute(
          builder: (context) => SellerProfileViewPage(
            sellerId: sellerId,
            initialSellerData: sellerInfo,
            verificationType: _sellerBadge,
          ),
        ),
      );
    } else {
      _toast('Seller information not available');
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) return user.id;

    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      deviceId = _uuid.v4();
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }

  Future<void> _incrementViewsWithRPC() async {
    try {
      final productId = widget.productId ?? product['id']?.toString();
      if (productId == null) return;

      final fp = await _getOrCreateDeviceId();
      await EdgeFunctionsClient.instance.rpcProxy('increment_listing_views', params: {
        'p_listing_id': productId,
        'p_fp': fp,
      }, requireAuth: false);

      if (kDebugMode) {
        print('Views incremented via RPC for product: $productId');
      }
    } catch (e) {
      if (kDebugMode) print('Failed to increment views via RPC: $e');
    }
  }

  Future<void> _recordInquiry(String type) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final productId = widget.productId ?? product['id']?.toString();

      if (user == null || productId == null) {
        if (kDebugMode) {
          print('Cannot record inquiry: user=$user, productId=$productId');
        }
        return;
      }

      await Supabase.instance.client.from('inquiries').insert({
        'listing_id': productId,
        'user_id': user.id,
        'type': type,
      });

      if (kDebugMode) print('Inquiry recorded: $type for product: $productId');
    } catch (e) {
      if (kDebugMode) print('Failed to record inquiry: $e');
    }
  }

  void _prepareProductData() {
    if (widget.productData != null) {
      product = Map<String, dynamic>.from(widget.productData!);
      if (product['id'] == null && widget.productId != null) {
        product['id'] = widget.productId;
      }
    } else if (widget.productId != null) {
      final found = ListingStore.i.find(widget.productId!);
      if (found != null && found.isNotEmpty) {
        product = Map<String, dynamic>.from(found);
      } else {
        product = {'id': widget.productId};
      }
    } else {
      product = {};
    }

    final imgs = product['images'] ?? product['image_urls'] ?? product['image'];
    if (imgs is List && imgs.isNotEmpty) {
      productImages = imgs.map((e) => e.toString()).toList();
    } else if (imgs is String && imgs.isNotEmpty) {
      productImages = [imgs];
    }

    if (productImages.isEmpty) {
      productImages = ['assets/images/placeholder.jpg'];
    }

    _sellerId = (product['user_id'] ?? product['seller_id'])?.toString();

    // ✅ [改动 2.1] 如果此时已经有id，就排队做一次奖励检查（下一帧触发）
    _queueRewardCheck();
  }

  Future<void> _hydrateListingFromCloudIfNeeded() async {
    try {
      final dynamicId = widget.productId ?? (product['id']?.toString());
      if (dynamicId == null || dynamicId.isEmpty) return;

      if (kDebugMode) {
        print('=== 从云端加载商品数据 ===');
        print('商品ID: $dynamicId');
      }

      final row = await Supabase.instance.client
          .from('listings')
          .select(
              'id, user_id, phone, title, images, image_urls, city, price, description, created_at, views_count')
          .eq('id', dynamicId)
          .maybeSingle();

      if (kDebugMode) print('从数据库获取的数据: $row');

      if (row == null) return;

      bool isBlank(dynamic v) =>
          v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is num && (v.isNaN));

      bool needLoadSeller = false;

      if (mounted) {
        setState(() {
          if (!isBlank(row['id'])) product['id'] = row['id'];
          if (!isBlank(row['user_id'])) {
            final oldUserId = product['user_id'] ?? product['seller_id'];
            if (oldUserId != row['user_id']) needLoadSeller = true;
            product['user_id'] = row['user_id'];
            product['seller_id'] = row['user_id'];
            _sellerId = row['user_id']?.toString();
          }
          if (!isBlank(row['phone'])) {
            product['sellerPhone'] = row['phone'];
            product['phone'] = row['phone'];
          }
          if (_isPlaceholderText(product['title']?.toString()) &&
              !isBlank(row['title'])) {
            product['title'] = row['title'];
          }
          if (_isPlaceholderText(product['city']?.toString()) &&
              !isBlank(row['city'])) {
            product['city'] = row['city'];
            product['location'] = row['city'];
          }
          if (_isPlaceholderText(product['location']?.toString()) &&
              !isBlank(row['city'])) {
            product['location'] = row['city'];
          }
          if (_isPlaceholderText(product['price']?.toString()) &&
              !isBlank(row['price'])) {
            product['price'] = row['price'];
          }
          if (_isPlaceholderText(product['description']?.toString()) &&
              !isBlank(row['description'])) {
            product['description'] = row['description'];
          }
          if (isBlank(product['created_at']) && !isBlank(row['created_at'])) {
            product['created_at'] = row['created_at'];
          }
          if (!isBlank(row['views_count'])) {
            product['views_count'] = row['views_count'];
          }

          final rowImages = (row['images'] ?? row['image_urls']);
          final isPlaceholderList = productImages.isEmpty ||
              (productImages.length == 1 &&
                  productImages.first.contains('placeholder'));

          if (isPlaceholderList && rowImages is List && rowImages.isNotEmpty) {
            productImages = rowImages.map((e) => e.toString()).toList();
            product['images'] = productImages;

            Future.microtask(() => _precacheAllImages());
          }
        });

        if (kDebugMode) {
          print('✅ 商品数据更新完成，user_id: ${product['user_id']}');
        }

        // ✅ [改动 2.3] 云端回填id后，再排队触发奖励检查（避免第一次postFrame没id）
        _queueRewardCheck();

        if (needLoadSeller && !isBlank(row['user_id'])) {
          if (kDebugMode) print('🔄 检测到新的user_id，重新加载卖家信息');
          await _loadSellerInfo();
          await _loadSellerVerification();
        } else {
          _fetchBlockStatus();
          _loadSellerVerification();
        }
      }
    } catch (e) {
      if (kDebugMode) print('hydrate listing failed: $e');
    }
  }

  bool _isPlaceholderText(String? text) {
    if (text == null || text.trim().isEmpty) return true;
    final placeholders = [
      'Product',
      'No description available',
      'Zimbabwe',
      r'$0',
      'Seller',
      'Recently'
    ];
    return placeholders.contains(text.trim());
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontSize: 12.sp)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        margin: EdgeInsets.all(12.w),
      ),
    );
  }

  bool get _isOwnListing {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final seller =
        (_sellerId ?? (product['user_id'] ?? product['seller_id'])?.toString());
    return me != null && seller != null && me == seller;
  }

  Future<void> _showSelfListingInfo({required String actionName}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This is your own listing'),
        content: Text("You can't $actionName on your own listing."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureAllowedForContact({String actionName = 'contact'}) async {
    final verified = await VerificationGuard.ensureVerifiedOrPrompt(context);
    if (!verified) return false;

    if (_sellerId == null) {
      _toast('Seller information not available');
      return false;
    }

    final me = Supabase.instance.client.auth.currentUser?.id;
    final sellerIdNow =
        _sellerId ?? (product['user_id'] ?? product['seller_id'])?.toString();
    if (me != null && sellerIdNow != null && me == sellerIdNow) {
      await _showSelfListingInfo(actionName: actionName);
      return false;
    }

    if (_blockStatus.otherBlockedMe) {
      _toast("You can't $actionName because the seller has blocked you.");
      return false;
    }
    if (_blockStatus.iBlockedOther) {
      final confirm = await _confirmDialog(
        title: 'Unblock to continue?',
        message:
            'You have blocked this seller. Do you want to unblock and continue?',
        confirmText: 'Unblock',
      );
      if (confirm != true) return false;
      final ok = await OfferService.unblockUser(blockedId: _sellerId!);
      if (!ok) {
        _toast('Failed to unblock this seller');
        return false;
      }
      await _fetchBlockStatus();
      if (_blockStatus.iBlockedOther) return false;
    }
    return true;
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    String confirmText = 'OK',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmText)),
        ],
      ),
    );
  }

  Future<void> _checkFavoritesStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    final id = widget.productId ?? product['id']?.toString();

    if (user == null || id == null || id.isEmpty) {
      if (mounted) setState(() => _isInFavorites = false);
      return;
    }

    try {
      if (kDebugMode) print('Checking favorites status for product: $id');

      final isInFavorites = await DualFavoritesService.isInFavorites(
        userId: user.id,
        listingId: id,
      );

      if (mounted) setState(() => _isInFavorites = isInFavorites);
      if (kDebugMode) print('Favorites status check result: $isInFavorites');
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error checking favorites status: $e');
        print('Stack trace: $stackTrace');
      }
      if (mounted) setState(() => _isInFavorites = false);
    }
  }

  // ✅ [收藏优化] 乐观更新策略 - 立即响应用户操作，后台同步数据
  Future<void> _toggleFavorites() async {
    final user = Supabase.instance.client.auth.currentUser;
    final id = widget.productId ?? product['id']?.toString();

    if (user == null) {
      _toast('Please login to add to favorites');
      return;
    }

    if (id == null || id.isEmpty) {
      _toast('Product ID not available');
      return;
    }

    if (_isFavoritesLoading) return;

    // ✅ [乐观更新 第1步] 立即更新 UI，用户感觉瞬间响应
    final previousStatus = _isInFavorites;
    final optimisticStatus = !_isInFavorites;

    setState(() {
      _isInFavorites = optimisticStatus;
      _isFavoritesLoading = true;
    });

    // ✅ [乐观更新 第2步] 后台异步同步数据
    try {
      final connectionTest =
          await DualFavoritesService.testConnection(userId: user.id);
      if (!connectionTest) {
        throw Exception('Database connection failed');
      }

      final actualStatus = await DualFavoritesService.toggleFavorite(
        userId: user.id,
        listingId: id,
      );

      if (!mounted) return;

      // ✅ [乐观更新 第3步] 如果实际结果与预期不符，更正 UI
      if (actualStatus != optimisticStatus) {
        if (kDebugMode) {
          print(
              '⚠️ Optimistic update mismatch: expected=$optimisticStatus, actual=$actualStatus');
        }
        setState(() => _isInFavorites = actualStatus);
      }

      // 通知其他组件
      FavoritesUpdateService().notifyFavoriteChanged(
        listingId: id,
        isAdded: actualStatus,
        listingData: actualStatus ? Map<String, dynamic>.from(product) : null,
      );

      // 显示成功提示
      _toast(actualStatus
          ? 'Added to favorites and wishlist successfully!'
          : 'Removed from favorites and wishlist');

      // 发送通知
      if (actualStatus) _sendWishlistNotification();
    } catch (e) {
      // ✅ [乐观更新 第4步] 失败时回滚 UI
      if (kDebugMode) {
        print('❌ Failed to update favorites: $e');
        print('🔄 Rolling back to previous status: $previousStatus');
      }

      if (!mounted) return;
      setState(() => _isInFavorites = previousStatus);

      _toast('Failed to update favorites');

      // 重新检查真实状态
      _checkFavoritesStatus();
    } finally {
      if (mounted) setState(() => _isFavoritesLoading = false);
    }
  }

  Future<void> _sendWishlistNotification() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final sellerId = product['user_id'] ?? product['seller_id'];
      final id = widget.productId ?? product['id']?.toString();

      if (id == null || sellerId == null || sellerId == user.id) return;

      String? userName;
      try {
        final profile = await Supabase.instance.client
            .from('public_profiles')
            .select('full_name')
            .eq('id', user.id)
            .maybeSingle();
        userName = profile?['full_name'];
      } catch (_) {}

      await NotificationService.createWishlistNotification(
        sellerId: sellerId,
        likerId: user.id,
        listingId: id,
        listingTitle: product['title'] ?? 'Unknown Item',
        likerName: userName,
      );
    } catch (_) {}
  }

  Future<void> _makePhoneCall() async {
    if (!await _ensureAllowedForContact(actionName: 'make a call')) return;

    final rawPhone =
        product['sellerPhone']?.toString().trim().isNotEmpty == true
            ? product['sellerPhone'].toString()
            : (product['phone']?.toString() ?? '');

    if (rawPhone.isEmpty) {
      _toast('Phone number not available');
      return;
    }

    await _recordInquiry('call');

    try {
      final cleanPhone = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
      final uri = Uri(scheme: 'tel', path: cleanPhone);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _toast('Unable to make phone call. Your device may not support it.');
      }
    } catch (e) {
      _toast('Failed to make phone call: ${e.toString()}');
    }
  }

  // 🚨 智能号码清洗与转换（与入库清洗逻辑保持一致）
  String _cleanPhoneForWhatsApp(String raw) {
    if (raw.isEmpty) return '';
    String rawTrimmed = raw.trim();
    String clean = rawTrimmed.replaceAll(RegExp(r'[^\d]'), '');

    // A. 如果原始输入带 + 号，信任其区号，仅去除非数字，不触发补齐
    if (rawTrimmed.startsWith('+')) return clean;

    // B. 津巴布韦 10 位本地格式 (077...) -> 转 26377...
    if (clean.startsWith('0') && clean.length == 10) {
      return '263' + clean.substring(1);
    }

    // C. 津巴布韦 9 位短号格式 (77...) -> 转 26377...
    if (clean.length == 9 && (clean.startsWith('71') || clean.startsWith('77') || clean.startsWith('78'))) {
      return '263' + clean;
    }

    // D. 其他情况返回清洗后的数字（可能为空）
    return clean;
  }

  Future<void> _openWhatsApp() async {
    if (!await _ensureAllowedForContact(actionName: 'contact via WhatsApp')) {
      return;
    }

    final raw = product['sellerPhone']?.toString().trim().isNotEmpty == true
        ? product['sellerPhone'].toString()
        : (product['phone']?.toString() ?? '');

    await _recordInquiry('whatsapp');

    final message =
        "Hi, I'm interested in your ${product['title'] ?? 'item'} listed on Swaply for ${product['price'] ?? 'the listed price'}. Is it still available?";
    final encMsg = Uri.encodeComponent(message);
    
    // 🚨 智能号码清洗与转换（与入库清洗逻辑保持一致）
    String digits = _cleanPhoneForWhatsApp(raw);

    Future<bool> tryLaunch(Uri u) async {
      if (await canLaunchUrl(u)) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    }

    // 长度校验 (WhatsApp 要求至少 10 位有效数字)
    if (digits.length >= 10) {
      // 使用 https 链接兼容性更好，确保不包含 + 号（只保留纯数字）
      final uri = Uri.parse('https://wa.me/$digits?text=$encMsg');
      if (await tryLaunch(uri)) {
        return;
      }
    }

    // 降级处理 (提示用户号码无效，仅打开 App)
    if (digits.isNotEmpty && digits.length < 5) {
        _toast('Seller phone number invalid ($raw). Opening WhatsApp main page.');
    }
    
    // 打开不带号码的链接
    final fallbackUri = Uri.parse('https://wa.me/?text=$encMsg');
    if (await tryLaunch(fallbackUri)) return;

    // 最老的回退方案
    if (await tryLaunch(Uri.parse('whatsapp://send?text=$encMsg'))) return;

    final market = Uri.parse('market://details?id=com.whatsapp');
    final playWeb =
        Uri.parse('https://play.google.com/store/apps/details?id=com.whatsapp');
    if (await tryLaunch(market) || await tryLaunch(playWeb)) return;

    await Clipboard.setData(ClipboardData(text: message));
    _toast('WhatsApp not available. Message copied.');
  }

  void _showMakeOfferDialog() async {
    if (!await _ensureAllowedForContact(actionName: 'make an offer')) return;

    final user = Supabase.instance.client.auth.currentUser;
    final id = widget.productId ?? product['id']?.toString();

    if (user == null) {
      _toast('Please login to make offers');
      return;
    }
    if (id == null) {
      _toast('Product not available');
      return;
    }

    final sellerId = product['user_id'] ?? product['seller_id'];
    if (sellerId == null) {
      _toast('Seller information not available');
      return;
    }

    final TextEditingController offerController = TextEditingController();
    final TextEditingController messageController = TextEditingController();
    final priceStr = product['price']?.toString() ?? r'$0';
    final cleanPrice = priceStr.replaceAll(r'$', '').replaceAll(',', '');
    final price = double.tryParse(cleanPrice) ?? 0;

    final quickOffers = [
      price * 0.8,
      price * 0.85,
      price * 0.9,
      price * 0.95,
    ].where((offer) => offer > 0).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (BuildContext sheetCtx) {
        final keyboardPadding = MediaQuery.of(sheetCtx).viewInsets.bottom;
        final safeAreaPadding = MediaQuery.of(sheetCtx).padding.bottom;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16.r),
              topRight: Radius.circular(16.r),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: keyboardPadding > 0
                ? keyboardPadding + 8.h
                : safeAreaPadding + 16.h,
            top: 16.h,
            left: 16.w,
            right: 16.w,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32.w,
                  height: 3.h,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Make an Offer',
                          style: TextStyle(
                              fontSize: 18.sp, fontWeight: FontWeight.bold)),
                      SizedBox(height: 2.h),
                      Text('Current Price: ${product['price']}',
                          style: TextStyle(
                              fontSize: 12.sp, color: Colors.grey[600])),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    icon: Container(
                      padding: EdgeInsets.all(6.r),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, size: 16.r),
                    ),
                  ),
                ],
              ),
              if (quickOffers.isNotEmpty) ...[
                SizedBox(height: 16.h),
                Text('Quick Select',
                    style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
                SizedBox(height: 8.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: quickOffers.map((offer) {
                    final percentage =
                        price > 0 ? ((offer / price) * 100).round() : 0;
                    return InkWell(
                      onTap: () =>
                          offerController.text = offer.toStringAsFixed(0),
                      borderRadius: BorderRadius.circular(8.r),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            Text('\$${offer.toStringAsFixed(0)}',
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.bold)),
                            Text('$percentage%',
                                style: TextStyle(
                                    fontSize: 9.sp, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              SizedBox(height: 16.h),
              Text('Your Offer',
                  style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              SizedBox(height: 8.h),
              TextField(
                controller: offerController,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: r'$ ',
                  prefixStyle:
                      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
                  hintText: 'Enter amount',
                  hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontWeight: FontWeight.normal,
                      fontSize: 12.sp),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                    borderSide: BorderSide(color: _primaryBlue, width: 2.w),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                ),
              ),
              SizedBox(height: 12.h),
              Text('Message (Optional)',
                  style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
              SizedBox(height: 6.h),
              TextField(
                controller: messageController,
                maxLines: 2,
                style: TextStyle(fontSize: 12.sp),
                decoration: InputDecoration(
                  hintText: 'Add a message to the seller...',
                  hintStyle:
                      TextStyle(color: Colors.grey[400], fontSize: 11.sp),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.r),
                    borderSide: BorderSide(color: _primaryBlue, width: 2.w),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                ),
              ),
              SizedBox(height: 16.h),
              Container(
                width: double.infinity,
                height: 42.h,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [_primaryBlue, _primaryBlue.withOpacity(0.85)]),
                  borderRadius: BorderRadius.circular(8.r),
                  boxShadow: [
                    BoxShadow(
                        color: _primaryBlue.withOpacity(0.25),
                        blurRadius: 4.r,
                        offset: Offset(0, 2.h)),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isOfferLoading
                        ? null
                        : () async {
                            final offerText = offerController.text.trim();
                            if (offerText.isEmpty) {
                              _toast('Please enter offer amount');
                              return;
                            }
                            final amount = double.tryParse(offerText);
                            if (amount == null || amount <= 0) {
                              _toast('Please enter a valid offer amount');
                              return;
                            }
                            Navigator.pop(sheetCtx);
                            await _recordInquiry('offer');
                            await _sendOffer(
                              amount,
                              messageController.text.trim().isEmpty
                                  ? null
                                  : messageController.text.trim(),
                            );
                          },
                    borderRadius: BorderRadius.circular(8.r),
                    child: Center(
                      child: _isOfferLoading
                          ? SizedBox(
                              width: 16.w,
                              height: 16.h,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text('Send Offer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ✅ [Offer消息修复] 发送offer时同时发送消息
  Future<void> _sendOffer(double amount, String? message) async {
    if (!await _ensureAllowedForContact(actionName: 'make an offer')) return;

    final user = Supabase.instance.client.auth.currentUser;
    final id = widget.productId ?? product['id']?.toString();

    if (user == null || id == null) {
      _toast('Unable to send offer');
      return;
    }

    final sellerId = product['user_id'] ?? product['seller_id'];
    if (sellerId == null) {
      _toast('Seller information not available');
      return;
    }

    setState(() => _isOfferLoading = true);

    try {
      // 1️⃣ 创建 offer
      final result = await OfferService.createOffer(
        listingId: id,
        sellerId: sellerId,
        offerAmount: amount,
        message: message,
      );

      if (result == null) {
        _toast('Failed to send offer');
        return;
      }

      // 2️⃣ 如果有消息，发送到 MessageService
      if (message != null && message.isNotEmpty) {
        try {
          final offerId = result['id']?.toString();
          if (offerId != null) {
            await MessageService.sendMessage(
              offerId: offerId,
              receiverId: sellerId.toString(),
              message: message,
            );

            if (kDebugMode) {
              print('✅ Message sent successfully with offer');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Failed to send message with offer: $e');
          }
          // 消息发送失败不影响offer创建成功
        }
      }

      _toast('Offer sent successfully!');
    } catch (e) {
      if (e is PostgrestException && e.code == 'P0001') {
        await _showSelfListingInfo(actionName: 'make an offer');
      } else if (e.toString().toLowerCase().contains('pending offer')) {
        _toast('You already have a pending offer for this item');
      } else {
        _toast('Failed to send offer');
      }
    } finally {
      setState(() => _isOfferLoading = false);
    }
  }

  String _formatPrice(String? price) {
    if (price == null || price.isEmpty) return '\$: 0';
    if (price.startsWith(r'$')) {
      return price.replaceFirst(r'$', r'$: ');
    }
    return '\$: $price';
  }

  Map<String, String> _buildSharePayload() {
    final id = widget.productId ?? product['id']?.toString() ?? '';
    final title = (product['title']?.toString() ?? 'Item').trim();
    final city = (product['city'] ?? product['location'])?.toString();

    String priceStr = '';
    final dynamic p = product['price'];
    if (p != null) {
      if (p is num) {
        priceStr = p.toStringAsFixed(0);
      } else {
        final parsed = num.tryParse(p.toString());
        if (parsed != null) priceStr = parsed.toStringAsFixed(0);
      }
    }

    final url = 'https://swaply.cc/l/$id?ref=app';
    final cityPart = (city != null && city.isNotEmpty) ? ' ($city)' : '';
    final pricePart = priceStr.isNotEmpty ? ' • \$$priceStr' : '';
    final text = 'Check this on Swaply$cityPart: $title$pricePart\n$url';

    return {'title': title, 'text': text, 'url': url};
  }

  Future<void> _shareCurrentListing() async {
    final id = widget.productId ?? product['id']?.toString();
    if (id == null || id.isEmpty) {
      _toast('Unable to share: missing item id');
      return;
    }
    await _showCompactShareSheet();
  }

  // ✅ [UI修复] 修复分享弹窗锯齿问题 - 明确设置不透明背景色
  Future<void> _showCompactShareSheet() async {
    final payload = _buildSharePayload();
    final url = payload['url']!;
    final text = payload['text']!;
    final title = payload['title']!;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // ✅ 修复：改为true，允许内容滚动
      useSafeArea: true,
      useRootNavigator: true,
      backgroundColor: Colors.white, // ✅ 明确设置白色背景，避免锯齿
      elevation: 8, // ✅ 添加阴影增强视觉效果
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      clipBehavior: Clip.antiAlias, // ✅ 确保抗锯齿
      builder: (ctx) {
        final divider = Divider(height: 1, color: Colors.grey.withOpacity(.2));
        return Container(
          // ✅ 额外包裹一层白色容器，确保完全不透明
          color: Colors.white,
          child: ListView(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            children: [
              const SizedBox(height: 8),
              Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              _actionTile(
                icon: Icons.ios_share_rounded,
                iconColor: Colors.black87,
                text: 'Share via other apps',
                onTap: () async {
                  Navigator.pop(ctx);
                  await Share.share(text, subject: 'Swaply: $title');
                },
              ),
              divider,
              _actionTile(
                icon: Icons.link_rounded,
                iconColor: _primaryBlue,
                text: 'Copy link',
                subtitle: url,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  Navigator.pop(ctx);
                  _toast('Link copied');
                },
              ),
              divider,
              _actionTile(
                icon: Icons.chat_rounded,
                iconColor: const Color(0xFF25D366),
                text: 'Share to WhatsApp',
                onTap: () async {
                  Navigator.pop(ctx);
                  await ShareUtils.toWhatsApp(text: text);
                },
              ),
              divider,
              _actionTile(
                icon: Icons.send_rounded,
                iconColor: const Color(0xFF2AABEE),
                text: 'Share to Telegram',
                onTap: () async {
                  Navigator.pop(ctx);
                  await ShareUtils.toTelegram(url: url, text: text);
                },
              ),
              divider,
              _actionTile(
                icon: Icons.public_rounded,
                iconColor: const Color(0xFF1877F2),
                text: 'Share to Facebook',
                onTap: () async {
                  Navigator.pop(ctx);
                  await ShareUtils.toFacebook(url: url);
                },
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom + 6),
            ],
          ),
        );
      },
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String text,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 24, color: iconColor),
      title: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: (subtitle == null)
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.black.withOpacity(.45)),
            ),
      minLeadingWidth: 24,
      horizontalTitleGap: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      dense: false,
    );
  }

  Future<void> _openWhatsAppShare(String text) async {
    await ShareUtils.toWhatsApp(text: text);
  }

  Future<void> _openTelegramShare({
    required String url,
    required String text,
  }) async {
    await ShareUtils.toTelegram(url: url, text: text);
  }

  Future<void> _openFacebookShare(String url) async {
    await ShareUtils.toFacebook(url: url);
  }

  double _imageAreaHeight(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final double minH = 320.h;
    final double maxH = 540.h;
    final double target = screenH * 0.58;
    final clamped = target.clamp(minH, maxH);
    return clamped.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        key: const Key(QaKeys.listingDetailRoot),
        slivers: [
          SliverAppBar(
            expandedHeight: _imageAreaHeight(context),
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(background: _buildImageCarousel()),
            leading: IconButton(
              onPressed: _handleBack,
              icon: Icon(Icons.arrow_back, color: Colors.grey[800]),
              iconSize: 22,
              constraints: _topIconConstraints,
              padding: const EdgeInsets.all(10),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.ios_share_rounded, color: Colors.grey[800]),
                iconSize: _topIconSize,
                onPressed: _shareCurrentListing,
                tooltip: 'Share',
                constraints: _topIconConstraints,
                padding: const EdgeInsets.all(10),
              ),
              _isFavoritesLoading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: SizedBox(
                        width: _topIconSize,
                        height: _topIconSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                  : IconButton(
                      key: const Key(QaKeys.favoriteToggle),
                      icon: Icon(
                        _isInFavorites ? Icons.favorite : Icons.favorite_border,
                        color: _isInFavorites ? Colors.red : Colors.grey[800],
                      ),
                      iconSize: _topIconSize,
                      onPressed: _toggleFavorites,
                      tooltip: _isInFavorites ? 'Unfavorite' : 'Favorite',
                      constraints: _topIconConstraints,
                      padding: const EdgeInsets.all(10),
                    ),
              if (_sellerId != null)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: _onMoreMenu,
                  itemBuilder: (ctx) {
                    final items = <PopupMenuEntry<String>>[
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report'),
                      ),
                    ];
                    if (_blockStatus.iBlockedOther) {
                      items.add(const PopupMenuItem(
                        value: 'unblock',
                        child: Text('Unblock user'),
                      ));
                    } else {
                      items.add(const PopupMenuItem(
                        value: 'block',
                        child: Text('Block user'),
                      ));
                    }
                    return items;
                  },
                  icon: Icon(Icons.more_vert, color: Colors.grey[800]),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProductInfoCard(),
                    _buildSellerInfoCard(),
                    _buildBlockBanner(),
                    _buildDescriptionCard(),
                    SizedBox(height: 80.h),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBlockBanner() {
    if (_loadingBlock || _sellerId == null) return const SizedBox.shrink();
    if (!_blockStatus.otherBlockedMe && !_blockStatus.iBlockedOther) {
      return const SizedBox.shrink();
    }

    final isOtherBlockedMe = _blockStatus.otherBlockedMe;
    final color = isOtherBlockedMe ? Colors.red.shade50 : Colors.orange.shade50;
    final textColor =
        isOtherBlockedMe ? Colors.red.shade700 : Colors.orange.shade700;
    final icon = isOtherBlockedMe ? Icons.block : Icons.do_not_disturb_alt;

    final msg = isOtherBlockedMe
        ? "You can't contact this seller because they have blocked you."
        : "You have blocked this seller. Unblock to contact.";

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: textColor.withOpacity(.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: textColor),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(fontSize: 12.sp, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final bool own = _isOwnListing;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10.r,
            offset: Offset(0, -2.h),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 42.h,
                margin: EdgeInsets.only(right: 4.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_successGreen, _successGreen.withOpacity(.9)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: _successGreen.withOpacity(.2),
                      blurRadius: 4.r,
                      offset: Offset(0, 2.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: own
                      ? () => _showSelfListingInfo(actionName: 'make a call')
                      : _makePhoneCall,
                  icon: Icon(Icons.phone, size: 16.sp, color: Colors.white),
                  label: Text('Call',
                      style: TextStyle(
                          fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r)),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 42.h,
                margin: EdgeInsets.symmetric(horizontal: 3.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF25D366), Color(0xFF38E54D)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF25D366).withOpacity(.2),
                      blurRadius: 4.r,
                      offset: Offset(0, 2.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: own
                      ? () => _showSelfListingInfo(
                          actionName: 'contact via WhatsApp')
                      : _openWhatsApp,
                  icon: Icon(Icons.chat, size: 16.sp, color: Colors.white),
                  label: Text('WhatsApp',
                      style: TextStyle(
                          fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r)),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 42.h,
                margin: EdgeInsets.only(left: 4.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_primaryBlue, _primaryBlue.withOpacity(.9)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                  boxShadow: [
                    BoxShadow(
                      color: _primaryBlue.withOpacity(.2),
                      blurRadius: 4.r,
                      offset: Offset(0, 2.h),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: own
                      ? () => _showSelfListingInfo(actionName: 'make an offer')
                      : _showMakeOfferDialog,
                  icon:
                      Icon(Icons.local_offer, size: 16.sp, color: Colors.white),
                  label: Text('Offer',
                      style: TextStyle(
                          fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r)),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductInfoCard() {
    final viewCount = product['views_count']?.toString() ?? '0';
    final timePosted = _getTimePosted();

    return Container(
      margin: EdgeInsets.all(12.w),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product['title']?.toString() ?? 'Loading...',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
              height: 1.3,
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: _successGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(
                      color: _successGreen.withOpacity(0.3), width: 1),
                ),
                child: Text(
                  _formatPrice(product['price']?.toString()),
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: _successGreen,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        size: 12.sp, color: Colors.grey[600]),
                    SizedBox(width: 3.w),
                    Text('$viewCount views',
                        style: TextStyle(
                            fontSize: 11.sp, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  color: Colors.grey[600], size: 14.sp),
              SizedBox(width: 4.w),
              Expanded(
                child: Text(
                  product['location']?.toString() ??
                      product['city']?.toString() ??
                      'Location not specified',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timePosted.isNotEmpty) ...[
                SizedBox(width: 8.w),
                Text(timePosted,
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey[500])),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSellerInfoCard() {
    if (_loadingSeller) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 12.w),
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8.r,
              offset: Offset(0, 2.h),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 10.h,
                    width: 70.w,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Container(
                    height: 8.h,
                    width: 50.w,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final sellerName = sellerInfo?['full_name'] ?? 'Anonymous';
    final memberSince = _getSellerMemberSince();
    final avatarUrl = sellerInfo?['avatar_url'];

    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _navigateToSellerProfile,
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8.r,
                  offset: Offset(0, 2.h),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 14.sp, color: Colors.grey[600]),
                    SizedBox(width: 4.w),
                    Text('Seller Information',
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios,
                        size: 12.sp, color: Colors.grey[400]),
                  ],
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Hero(
                      tag: 'seller_avatar_${sellerInfo?['id'] ?? 'unknown'}',
                      child: VerifiedAvatar(
                        avatarUrl:
                            (avatarUrl?.isNotEmpty == true) ? avatarUrl : null,
                        radius: 18.r,
                        verificationType: _sellerBadge,
                        defaultIcon: Icons.person,
                        onTap: _navigateToSellerProfile,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sellerName,
                              style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800]),
                              overflow: TextOverflow.ellipsis),
                          if (memberSince.isNotEmpty) ...[
                            SizedBox(height: 2.h),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_outlined,
                                    size: 10.sp, color: Colors.grey[500]),
                                SizedBox(width: 2.w),
                                Text('Member since $memberSince',
                                    style: TextStyle(
                                        fontSize: 10.sp,
                                        color: Colors.grey[500])),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionCard() {
    final description =
        product['description']?.toString() ?? 'No description available';

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8.r,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 14.sp, color: Colors.grey[600]),
              SizedBox(width: 4.w),
              Text('Description',
                  style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700])),
            ],
          ),
          SizedBox(height: 8.h),
          Text(description,
              style: TextStyle(
                  fontSize: 12.sp, height: 1.4, color: Colors.grey[700])),
        ],
      ),
    );
  }

  Widget _buildImageCarousel() {
    if (productImages.isEmpty) {
      return Container(
        color: Colors.grey[100],
        child: Center(
          child: Icon(Icons.image, size: 40.sp, color: Colors.grey[400]),
        ),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() => _currentImageIndex = index);
            _precacheAdjacentImages(index);
          },
          itemCount: productImages.length,
          itemBuilder: (context, index) {
            final imageUrl = productImages[index];
            return GestureDetector(
              onTap: () => _showImageViewer(index),
              child: HeroMode(
                enabled: false,
                child: imageUrl.startsWith('http')
                    ? Image.network(
                        SupabaseImageConfig.getDetailUrl(imageUrl),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        cacheWidth: (MediaQuery.of(context).size.width *
                                MediaQuery.of(context).devicePixelRatio)
                            .round(),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: Colors.grey[100],
                            child: Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2,
                                color: _primaryBlue,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[100],
                          child: Center(
                            child: Icon(Icons.broken_image,
                                size: 40.sp, color: Colors.grey[400]),
                          ),
                        ),
                      )
                    : Image.asset(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[100],
                          child: Center(
                            child: Icon(Icons.broken_image,
                                size: 40.sp, color: Colors.grey[400]),
                          ),
                        ),
                      ),
              ),
            );
          },
        ),
        if (productImages.length > 1)
          Positioned(
            bottom: 12.h,
            right: 12.w,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(
                '${_currentImageIndex + 1}/${productImages.length}',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        if (productImages.length > 1)
          Positioned(
            bottom: 12.h,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                productImages.length > 5 ? 5 : productImages.length,
                (index) {
                  int actualIndex = index;
                  if (productImages.length > 5) {
                    if (_currentImageIndex < 2) {
                      actualIndex = index;
                    } else if (_currentImageIndex > productImages.length - 3) {
                      actualIndex = productImages.length - 5 + index;
                    } else {
                      actualIndex = _currentImageIndex - 2 + index;
                    }
                  }
                  return Container(
                    margin: EdgeInsets.symmetric(horizontal: 2.w),
                    width: actualIndex == _currentImageIndex ? 14.w : 5.w,
                    height: 5.h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3.r),
                      color: actualIndex == _currentImageIndex
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  void _showImageViewer(int initialIndex) async {
    final List<String> urls = productImages
        .where((e) => e.toString().isNotEmpty)
        .map((e) => e.toString())
        .toList();

    if (urls.isEmpty) {
      _toast('No images available');
      return;
    }

    if (_isViewerOpening) {
      if (kDebugMode) {
        print('⚠️ Image viewer already opening, ignoring duplicate tap');
      }
      return;
    }

    _isViewerOpening = true;

    try {
      if (!mounted) return;

      if (kDebugMode) {
        print('🖼️ Opening image viewer, initial index: $initialIndex');
      }

      await SafeNavigator.push(
        MaterialPageRoute(
          builder: (_) => _SafeImageViewer(
            urls: urls,
            initialIndex: initialIndex.clamp(0, urls.length - 1),
          ),
          fullscreenDialog: true,
          maintainState: true,
        ),
      );

      if (kDebugMode) print('✅ Image viewer closed successfully');
    } catch (e, stack) {
      if (kDebugMode) {
        print('❌ Failed to open image viewer: $e');
        print('Stack trace: $stack');
      }
      if (mounted) {
        _toast('Unable to open image viewer');
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        _isViewerOpening = false;
      }
    }
  }

  String _getTimePosted() {
    final createdAt = product['created_at']?.toString();
    if (createdAt == null || createdAt.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      if (difference.inDays > 30) {
        return '${((difference.inDays) / 30).floor()}mo ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (_) {
      return '';
    }
  }

  String _getSellerMemberSince() {
    final createdAt = sellerInfo?['created_at']?.toString();
    if (createdAt == null || createdAt.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(createdAt);
      return '${dateTime.year}';
    } catch (_) {
      return '';
    }
  }

  void _onMoreMenu(String value) async {
    if (_sellerId == null) return;
    switch (value) {
      case 'report':
        final type = await _pickReportType();
        if (type == null) return;
        final listingId = (widget.productId ?? product['id']?.toString());
        final ok = await OfferService.submitReport(
          reportedId: _sellerId!,
          type: type,
          description: null,
          listingId: listingId,
        );
        _toast(ok ? 'Report submitted' : 'Failed to submit report');
        break;
      case 'block':
        {
          final ok = await OfferService.blockUser(blockedId: _sellerId!);
          await _fetchBlockStatus();
          _toast(ok ? 'Blocked successfully' : 'Failed to block');
          break;
        }
      case 'unblock':
        {
          final ok = await OfferService.unblockUser(blockedId: _sellerId!);
          await _fetchBlockStatus();
          _toast(ok ? 'Unblocked' : 'Failed to unblock');
          break;
        }
    }
  }

  Future<String?> _pickReportType() async {
    const types = ['Spam', 'Scam', 'Harassment', 'Other'];
    return showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 8.h),
              Container(
                width: 42.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                itemCount: types.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(types[i]),
                  onTap: () => Navigator.pop(ctx, types[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SafeImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _SafeImageViewer({required this.urls, this.initialIndex = 0});

  @override
  State<_SafeImageViewer> createState() => _SafeImageViewerState();
}

class _SafeImageViewerState extends State<_SafeImageViewer> {
  late final PageController _pc;
  int _index = 0;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pc = PageController(initialPage: _index);

    if (kDebugMode) {
      print('🖼️ Image viewer initialized with ${widget.urls.length} images');
    }
  }

  @override
  void dispose() {
    if (kDebugMode) print('🗑️ Disposing image viewer PageController');
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (kDebugMode) print('🔙 Image viewer closed via back button');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _showChrome
            ? AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                title: Text(
                  '${_index + 1} / ${widget.urls.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              )
            : null,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (mounted) {
                setState(() => _showChrome = !_showChrome);
              }
            },
            child: PageView.builder(
              controller: _pc,
              onPageChanged: (i) {
                if (mounted) {
                  setState(() => _index = i);
                }
              },
              itemCount: widget.urls.length,
              itemBuilder: (_, i) {
                final url = widget.urls[i];
                final isNet = url.startsWith('http');

                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: isNet
                        ? Image.network(
                            SupabaseImageConfig.getDetailUrl(url),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: Colors.white,
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image,
                                      color: Colors.white54, size: 48),
                                  SizedBox(height: 8),
                                  Text('Failed to load image',
                                      style: TextStyle(color: Colors.white54)),
                                ],
                              ),
                            ),
                          )
                        : Image.file(
                            File(url),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image,
                                      color: Colors.white54, size: 48),
                                  SizedBox(height: 8),
                                  Text('Image not found',
                                      style: TextStyle(color: Colors.white54)),
                                ],
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
