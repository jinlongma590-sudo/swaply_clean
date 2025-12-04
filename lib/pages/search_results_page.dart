// lib/pages/search_results_page.dart
import 'package:flutter/foundation.dart'; // ✅ 仅为平台判断与 kIsWeb
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/listing_service.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/router/safe_navigator.dart';
class SearchResultsPage extends StatefulWidget {
  final String keyword; // 由首页传入
  final String? location; // 可选：城市筛选（'All Zimbabwe' 表示不过滤）

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _pinnedIds = {};
    });

    try {
      final kw = widget.keyword.trim();
      if (kw.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final city = (widget.location != null &&
          widget.location!.isNotEmpty &&
          widget.location != 'All Zimbabwe')
          ? widget.location
          : null;

      // 1) 列表检索
      final rows = await ListingService.search(
        keyword: kw,
        city: city,
        limit: 100,
        offset: 0,
      );

      // 2) 取当前关键字/城市下的置顶项
      _pinnedIds = await _fetchPinnedIds(kw, city);

      // 3) 合并 & 映射
      _items.addAll(rows.map(_mapRowToCard));
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 读取置顶的 listing_id 集合
  Future<Set<String>> _fetchPinnedIds(String kw, String? city) async {
    final sb = Supabase.instance.client;

    final data = await sb
        .from('search_pins_active')
        .select('listing_id, keyword, city')
        .filter('keyword', 'ilike', '%$kw%');

    final list = (data as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final filtered = city == null
        ? list
        : list.where((r) {
      final c = (r['city'] ?? '').toString();
      // 允许 city 为空（全津巴布韦生效）或精确匹配
      return c.isEmpty || c == city;
    });

    final ids = <String>{};
    for (final r in filtered) {
      final id = r['listing_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  Map<String, dynamic> _mapRowToCard(Map<String, dynamic> r) {
    final num? priceNum = r['price'] is num ? (r['price'] as num) : null;
    final priceText = priceNum != null
        ? '\$${priceNum.toStringAsFixed(0)}'
        : (r['price']?.toString() ?? '');

    final imgs = ListingService.readImages(r);
    final idStr = r['id']?.toString() ?? '';
    final isPinned = _pinnedIds.contains(idStr);

    return {
      'id': idStr,
      'title': r['title'] ?? '',
      'price': priceText,
      'location': r['city'] ?? '',
      'images': imgs,
      'postedDate': r['created_at'] ?? r['posted_at'],
      'pinned': isPinned,
      'full': r,
    };
  }

  void _openDetail(Map<String, dynamic> item) {
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
      backgroundColor: Colors.grey[100],
      // ✅ [MODIFIED] 替换 AppBar 为 _buildStandardAppBar 方法
      appBar: _buildStandardAppBar(context, title),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Text('Load failed: $_error',
            style: const TextStyle(color: Colors.red)),
      )
          : _items.isEmpty
          ? const Center(child: Text('No results'))
          : Column(
        children: [
          Container(
            alignment: Alignment.centerLeft,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            color: Colors.grey[50],
            child: Text(
              '${_items.length} ads found',
              style: const TextStyle(
                  color: Colors.grey, fontSize: 14),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final p = _items[i];
                final bool pinned = p['pinned'] == true;

                return GestureDetector(
                  onTap: () => _openDetail(p),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: pinned
                          ? Border.all(
                        color: const Color(0xFFFFA000),
                        width: 2,
                      )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        // 顶部图：强制铺满
                        AspectRatio(
                          aspectRatio:
                          1.0, // 方形展示，视觉更稳定
                          child: ClipRRect(
                            borderRadius:
                            const BorderRadius.vertical(
                                top: Radius.circular(14)),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _thumb(p),
                                ),
                                if (pinned) _pinnedRibbon(),
                              ],
                            ),
                          ),
                        ),
                        // 文本区域
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p['price']?.toString() ?? '',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p['title']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      size: 12,
                                      color: Colors.grey),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      p['location']
                                          ?.toString() ??
                                          '',
                                      maxLines: 1,
                                      overflow:
                                      TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey),
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
              },
            ),
          ),
        ],
      ),
    );
  }

  // ✅ [MODIFIED] 替换为标准 44pt Row 布局（移除魔法数）
  PreferredSizeWidget _buildStandardAppBar(
      BuildContext context, String title) {
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    const Color kBgColor = Color(0xFF2196F3); // 保持本页原有蓝色

    // Android/其它：保持原 AppBar
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

    // iOS：标准 44pt 导航条（无任何魔法数）
    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + 44),
      child: Container(
        color: kBgColor,                    // 颜色不变
        padding: EdgeInsets.only(top: statusBar),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 左侧返回（32×32）
                SizedBox(
                  width: 32, height: 32,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_back, // 此页面的返回图标
                          size: 18, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 标题 —— 与左右按钮垂直居中对齐
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,   // 保持居中
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),

                // 右侧占位（保证标题绝对居中；将来有按钮可替换）
                const SizedBox(width: 12),
                const SizedBox(width: 32, height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }


  /// 铺满容器（网络/本地都可），失败时灰底占位
  Widget _thumb(Map<String, dynamic> p) {
    // ... (此方法及以下所有方法保持不变)
    final imgs = p['images'];
    if (imgs is List && imgs.isNotEmpty) {
      final first = imgs.first.toString();
      if (first.startsWith('http')) {
        return Image.network(
          first,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imgPlaceholder(),
        );
      } else {
        return Image.asset(
          first,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imgPlaceholder(),
        );
      }
    }
    return _imgPlaceholder();
  }

  Widget _imgPlaceholder() => Container(
    color: Colors.grey[300],
    alignment: Alignment.center,
    child: const Icon(Icons.image, size: 50, color: Colors.grey),
  );

  /// 左上角 PINNED 徽标（与你首页风格一致的橙色）
  Widget _pinnedRibbon() {
    return Positioned(
      left: 8,
      top: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFA000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'PINNED',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}