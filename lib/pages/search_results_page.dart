// lib/pages/search_results_page.dart
// ✅ 修复：搜索置顶券可见性 + 置顶排序 + 地点信息被卡片完整包裹
// ✅ 性能：图片使用 CachedNetworkImage
// ✅ 样式统一：商品卡片与分类页面完全一致
// ✅ 诊断：完整日志追踪搜索流程
// ✅ 灵活匹配：支持分词匹配（"smart phone" 匹配 "phone"）

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:swaply/services/listing_service.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/router/safe_navigator.dart';

class SearchResultsPage extends StatefulWidget {
  final String keyword;
  final String? location;

  const SearchResultsPage({
    super.key,
    required this.keyword,
    this.location,
  });

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  final List<Map<String, dynamic>> _items = [];
  Set<String> _pinnedIds = <String>{};

  bool _loading = false;
  String? _error;

  static const Color _primaryBlue = Color(0xFF1877F2);
  static const Color _successGreen = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[SearchResults] ==================== PAGE INIT ====================');
    debugPrint('[SearchResults] keyword="${widget.keyword}"');
    debugPrint('[SearchResults] location="${widget.location}"');

    // ✅ 延迟加载，避免卡顿
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[SearchResults] PostFrameCallback - calling _load()');
      _load();
    });
  }

  Future<void> _load() async {
    debugPrint(
        '[SearchResults] ==================== _load() START ====================');

    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _pinnedIds = {};
    });

    try {
      final kw = widget.keyword.trim();
      debugPrint('[SearchResults] Trimmed keyword="$kw"');

      if (kw.isEmpty) {
        debugPrint('[SearchResults] ❌ Keyword is empty, aborting');
        setState(() => _loading = false);
        return;
      }

      final city = (widget.location != null &&
              widget.location!.isNotEmpty &&
              widget.location != 'All Zimbabwe')
          ? widget.location
          : null;

      debugPrint('[SearchResults] 🔍 Calling ListingService.search()');
      debugPrint('[SearchResults]   - keyword: "$kw"');
      debugPrint('[SearchResults]   - city: $city');

      final startTime = DateTime.now();

      // 1) 列表检索
      final rows = await ListingService.search(
        keyword: kw,
        city: city,
        limit: 100,
        offset: 0,
      );

      final searchDuration =
          DateTime.now().difference(startTime).inMilliseconds;
      debugPrint(
          '[SearchResults] ✅ Got ${rows.length} results in ${searchDuration}ms');

      // 2) 读取置顶项
      debugPrint('[SearchResults] Fetching pinned IDs...');
      _pinnedIds = await _fetchPinnedIds(kw, city);
      debugPrint(
          '[SearchResults] Got ${_pinnedIds.length} pinned items: $_pinnedIds');

      // 3) 合并 & 映射
      debugPrint('[SearchResults] Mapping rows to cards...');
      _items.addAll(rows.map(_mapRowToCard));
      debugPrint('[SearchResults] Mapped ${_items.length} items');

      // 4) ✅ 置顶优先显示，其次按发布时间倒序
      debugPrint('[SearchResults] Sorting items...');
      _items.sort((a, b) {
        final ap = a['pinned'] == true;
        final bp = b['pinned'] == true;
        if (ap != bp) return ap ? -1 : 1;

        DateTime parseTime(dynamic v) {
          if (v is DateTime) return v;
          if (v is String) return DateTime.tryParse(v) ?? DateTime(1970);
          return DateTime(1970);
        }

        final at = parseTime(a['postedDate']);
        final bt = parseTime(b['postedDate']);
        return bt.compareTo(at);
      });

      final pinnedCount = _items.where((item) => item['pinned'] == true).length;
      debugPrint(
          '[SearchResults] ✅ Final list: ${_items.length} items ($pinnedCount pinned)');
    } catch (e, stackTrace) {
      debugPrint('[SearchResults] ❌ ERROR: $e');
      debugPrint('[SearchResults] ❌ Stack: $stackTrace');
      _error = e.toString();
    } finally {
      if (mounted) {
        debugPrint('[SearchResults] Setting _loading = false');
        setState(() => _loading = false);
      }
    }

    debugPrint(
        '[SearchResults] ==================== _load() END ====================');
  }

  /// ✅ 获取置顶 IDs（灵活分词匹配）
  /// 支持：
  /// - 搜 "smart phone" 匹配 pin="phone"
  /// - 搜 "iphone" 匹配 pin="phone"
  /// - 搜 "car rental" 匹配 pin="car" 或 pin="rental"
  Future<Set<String>> _fetchPinnedIds(String kw, String? city) async {
    debugPrint('[SearchResults] _fetchPinnedIds START');
    debugPrint('[SearchResults]   - keyword: "$kw"');
    debugPrint('[SearchResults]   - city: $city');

    try {
      final sb = Supabase.instance.client;

      // 🔐 游客降级：search_pins 表仅允许 authenticated 读取
      final currentUser = sb.auth.currentUser;
      if (currentUser == null) {
        debugPrint('[SearchResults] 未登录用户，跳过置顶查询');
        return <String>{};
      }

      // ✅ 查询所有有效的置顶（视图已经过滤了时间范围）
      final data = await sb
          .from('search_pins_active')
          .select('listing_id, keyword, city, rank')
          .order('rank', ascending: false); // 按 rank 排序

      final list = (data as List?)?.cast<Map<String, dynamic>>() ?? const [];
      debugPrint('[SearchResults] Got ${list.length} active pinned records');

      // ✅ 前端灵活匹配：支持分词
      final ids = <String>{};
      final searchWords = _extractKeywords(kw); // 分词

      debugPrint('[SearchResults] Search words: $searchWords');

      for (final r in list) {
        final id = r['listing_id']?.toString();
        if (id == null || id.isEmpty) continue;

        final pinKw = (r['keyword'] ?? '').toString().toLowerCase();
        final pinCity = (r['city'] ?? '').toString();

        // ✅ 关键词匹配：灵活分词匹配
        final kwMatch = _isKeywordMatch(searchWords, pinKw);

        // ✅ 城市匹配：精确或全局
        final cityMatch = city == null ||
            city.isEmpty ||
            city == 'All Zimbabwe' ||
            pinCity.isEmpty ||
            pinCity == city;

        debugPrint(
            '[SearchResults]   Pin: id=$id, keyword="$pinKw", city="$pinCity"');
        debugPrint(
            '[SearchResults]   → kwMatch=$kwMatch, cityMatch=$cityMatch');

        if (kwMatch && cityMatch) {
          debugPrint('[SearchResults]   ✅ MATCHED');
          ids.add(id);
        }
      }

      debugPrint(
          '[SearchResults] _fetchPinnedIds END - ${ids.length} matched IDs');
      return ids;
    } catch (e, stackTrace) {
      debugPrint('[SearchResults] ❌ _fetchPinnedIds ERROR: $e');
      debugPrint('[SearchResults] Stack: $stackTrace');
      return {}; // 出错返回空，不影响搜索结果
    }
  }

  /// ✅ 分词：提取关键词
  /// 例如："smart phone" → ["smart", "phone"]
  /// 例如："car rental service" → ["car", "rental", "service"]
  List<String> _extractKeywords(String text) {
    return text
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+')) // 按空格分割
        .where((w) => w.length >= 2) // 过滤太短的词（如 "a", "i"）
        .toList();
  }

  /// ✅ 灵活关键词匹配
  ///
  /// 匹配规则：
  /// 1. pinKw 为空 → 全局置顶 → 总是匹配 ✅
  /// 2. 搜索词任意一个单词 与 pinKw 任意一个单词 有包含关系 → 匹配 ✅
  ///
  /// 示例：
  /// - 搜 "smart phone"，pin="phone" → ✅（"phone" ↔ "phone"）
  /// - 搜 "phone"，pin="smart phone" → ✅（"phone" ↔ "phone"）
  /// - 搜 "iphone 12"，pin="phone" → ✅（"iphone" 包含 "phone"）
  /// - 搜 "smartphone"，pin="phone" → ✅（"smartphone" 包含 "phone"）
  /// - 搜 "car rental"，pin="car" → ✅（"car" ↔ "car"）
  /// - 搜 "car"，pin="truck" → ❌（无交集）
  bool _isKeywordMatch(List<String> searchWords, String pinKw) {
    // 1. 空 keyword = 全局置顶
    if (pinKw.isEmpty) {
      debugPrint('[SearchResults]     → Global pin (empty keyword)');
      return true;
    }

    // 2. 分词 pin keyword
    final pinWords = _extractKeywords(pinKw);

    if (pinWords.isEmpty) {
      debugPrint('[SearchResults]     → Global pin (no valid words)');
      return true;
    }

    // 3. 双向匹配：搜索词 ↔ pin词，任意包含关系即匹配
    for (final searchWord in searchWords) {
      for (final pinWord in pinWords) {
        // 双向包含：A包含B 或 B包含A
        if (searchWord.contains(pinWord) || pinWord.contains(searchWord)) {
          debugPrint(
              '[SearchResults]     → ✅ Match: "$searchWord" ↔ "$pinWord"');
          return true;
        }
      }
    }

    debugPrint('[SearchResults]     → ❌ No match');
    return false;
  }

  Map<String, dynamic> _mapRowToCard(Map<String, dynamic> r) {
    final num? priceNum = r['price'] is num ? (r['price'] as num) : null;
    final priceText = priceNum != null
        ? '\$${priceNum.toStringAsFixed(0)}'
        : (r['price']?.toString() ?? '');

    final imgs = ListingService.readImages(r);
    final idStr = r['id']?.toString() ?? '';
    final isPinned = _pinnedIds.contains(idStr);

    debugPrint(
        '[SearchResults] Mapping item: id=$idStr, title="${r['title']}", pinned=$isPinned');

    return {
      'id': idStr,
      'title': r['title'] ?? '',
      'price': priceText,
      'price_num': priceNum,
      'location': r['city'] ?? '',
      'images': imgs,
      'postedDate': r['created_at'] ?? r['posted_at'],
      'pinned': isPinned,
      'full': r,
    };
  }

  void _openDetail(Map<String, dynamic> item) {
    debugPrint('[SearchResults] Opening detail for: ${item['id']}');

    final full = (item['full'] as Map?) ?? {};
    final images = (item['images'] as List?) ?? [];

    final pdData = {
      'id': item['id'],
      'title': item['title'],
      'price': item['price'],
      'location': item['location'],
      'images': images,
      'postedDate': item['postedDate'] ?? full['created_at'],
      'description': full['description'] ?? '',
      'sellerName': full['name'] ?? '',
      'sellerPhone': full['phone'] ?? '',
      'category': full['category'] ?? '',
    };

    SafeNavigator.push(
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          productId: item['id']?.toString(),
          productData: pdData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Results for "${widget.keyword}"';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildStandardAppBar(context, title),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryBlue))
          : _error != null
              ? _buildErrorState()
              : _items.isEmpty
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        _buildCompactCountBar(),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            color: _primaryBlue,
                            child: GridView.builder(
                              padding: EdgeInsets.all(12.w),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.66,
                                crossAxisSpacing: 8.w,
                                mainAxisSpacing: 8.h,
                              ),
                              itemCount: _items.length,
                              itemBuilder: (_, i) {
                                final p = _items[i];
                                return _buildProductCard(p);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  PreferredSizeWidget _buildStandardAppBar(BuildContext context, String title) {
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    const Color kBgColor = Color(0xFF2196F3);

    if (!isIOS) {
      return AppBar(
        backgroundColor: kBgColor,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: false,
        elevation: 0,
      );
    }

    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + 44),
      child: Container(
        color: kBgColor,
        padding: EdgeInsets.only(top: statusBar),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_back,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const SizedBox(width: 32, height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactCountBar() {
    final pinnedCount = _items.where((item) => item['pinned'] == true).length;
    final totalCount = _items.length;

    return Container(
      alignment: Alignment.centerLeft,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: _primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: _primaryBlue.withOpacity(0.3)),
            ),
            child: Text(
              '$totalCount ${totalCount == 1 ? 'ad' : 'ads'} found',
              style: TextStyle(
                color: _primaryBlue,
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (pinnedCount > 0) ...[
            SizedBox(width: 6.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.orange[300]!, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.push_pin, size: 8.sp, color: Colors.orange[700]),
                  SizedBox(width: 1.w),
                  Text(
                    '$pinnedCount featured',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 8.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> p) {
    final bool pinned = p['pinned'] == true;

    return GestureDetector(
      onTap: () => _openDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border:
              pinned ? Border.all(color: Colors.orange[400]!, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: pinned
                  ? Colors.orange.withOpacity(0.15)
                  : Colors.black.withOpacity(0.03),
              blurRadius: pinned ? 8 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildThumb(p)),
                  if (pinned)
                    Positioned(
                      left: 6.w,
                      top: 6.h,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: Colors.orange[600],
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          'FEATURED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7.sp,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(6.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p['price']?.toString().isNotEmpty ?? false)
                    Text(
                      p['price']?.toString() ?? '',
                      style: TextStyle(
                        color: _successGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.sp,
                      ),
                    ),
                  SizedBox(height: 2.h),
                  Text(
                    p['title']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 8.sp, color: Colors.grey[500]),
                      SizedBox(width: 1.w),
                      Expanded(
                        child: Text(
                          p['location']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 8.sp, color: Colors.grey[600]),
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

  Widget _buildThumb(Map<String, dynamic> p) {
    final imgs = p['images'];
    String? src;

    if (imgs is List && imgs.isNotEmpty) {
      src = imgs.first.toString();
    } else if (p['image'] != null) {
      src = p['image'].toString();
    }

    if (src == null || src.isEmpty) return _buildImagePlaceholder();

    Widget imageWidget;

    if (src.startsWith('http')) {
      imageWidget = CachedNetworkImage(
        imageUrl: src,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        memCacheWidth: 600,
        memCacheHeight: 600,
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _primaryBlue,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildImagePlaceholder(),
      );
    } else if (src.startsWith('/') || src.startsWith('file:')) {
      imageWidget = Image.file(
        File(src.replaceFirst('file://', '')),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    } else {
      imageWidget = Image.asset(
        src,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
      child: SizedBox.expand(child: imageWidget),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(Icons.image, size: 24.sp, color: Colors.grey[400]),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40.sp, color: Colors.red[400]),
          SizedBox(height: 10.h),
          Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 4.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              'Failed to load search results. Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.sp, color: Colors.grey[600]),
            ),
          ),
          SizedBox(height: 12.h),
          ElevatedButton.icon(
            onPressed: _load,
            icon: Icon(Icons.refresh, size: 14.sp),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.r),
              ),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 50.sp, color: Colors.grey[400]),
          SizedBox(height: 12.h),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 6.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              'We couldn\'t find any listings matching "${widget.keyword}". Try different keywords or check back later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.grey[600],
                height: 1.3,
              ),
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton.icon(
            onPressed: _load,
            icon: Icon(Icons.refresh, size: 14.sp),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6.r),
              ),
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            ),
          ),
        ],
      ),
    );
  }
}
