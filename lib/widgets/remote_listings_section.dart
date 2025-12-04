// lib/widgets/remote_listings_section.dart
import 'package:flutter/material.dart';
import 'package:swaply/config.dart';
import 'package:swaply/listing_api.dart';
import 'package:swaply/pages/category_products_page.dart';
// 使用集中路由：引入 root_nav 的 navPush（命名路由）
import 'package:swaply/router/root_nav.dart';
import 'package:swaply/router/safe_navigator.dart';
/// 首页/专区用的远端卡片列表区块
/// - [title] 区块标题
/// - [categoryId] 传 null 显示所有；否则传首页用的 id，比如 'jobs'、'vehicles'...
/// - [city] 传 null 显示全部城市
/// - [sort] 'newest' | 'price_low' | 'price_high'
/// - [limit] 每次加载多少
class RemoteListingsSection extends StatefulWidget {
  final String title;
  final String? categoryId;
  final String? city;
  final String sort;
  final int limit;
  final bool showSeeAllButton;

  const RemoteListingsSection({
    super.key,
    required this.title,
    this.categoryId,
    this.city,
    this.sort = 'newest',
    this.limit = 12,
    this.showSeeAllButton = true,
  });

  @override
  State<RemoteListingsSection> createState() => _RemoteListingsSectionState();
}

class _RemoteListingsSectionState extends State<RemoteListingsSection> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _offset = 0;
      _hasMore = true;
    });
    try {
      final page = await _fetch(offset: 0);
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= widget.limit;
        _offset = page.length;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(offset: _offset);
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= widget.limit;
        _offset += page.length;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 把首页用的 categoryId 转到数据库里的分类名（与你表里保持一致）
  String _categoryIdToDb(String id) {
    const map = {
      'vehicles': 'Vehicles',
      'property': 'Property',
      'beauty_personal_care': 'Beauty and Personal Care',
      'jobs': 'Jobs',
      'babies_kids': 'Babies and Kids',
      'services': 'Services',
      'leisure_activities': 'Leisure Activities',
      'repair_construction': 'Repair and Construction',
      'home_furniture_appliances': 'Home Furniture and Appliances',
      'pets': 'Pets',
      'electronics': 'Electronics',
      'phones': 'Phones and Tablets',
      'seeking_work_cvs': 'Seeking Work and CVs',
      'fashion': 'Fashion',
      'food_agriculture_drinks': 'Food Agriculture and Drinks',
    };
    return map[id] ?? id;
  }

  /// 远端拉取 + 本地排序 + 映射为卡片结构
  Future<List<Map<String, dynamic>>> _fetch({required int offset}) async {
    if (kUseRemoteData) {
      final categoryDb = widget.categoryId == null
          ? null
          : _categoryIdToDb(widget.categoryId!);

      // ⚠️ 不再传 sort，避免 “The named parameter 'sort' isn't defined”
      final rows = await ListingApi.fetchListings(
        category: categoryDb,
        city: widget.city,
        limit: widget.limit,
        offset: offset,
      );

      // 在内存里按 widget.sort 排序
      final sorted = List<Map<String, dynamic>>.from(rows);
      _applySortOnRaw(sorted, widget.sort);

      // 映射为前端卡片数据
      return sorted.map<Map<String, dynamic>>((r) {
        final num? priceNum = r['price'] is num ? (r['price'] as num) : null;
        final priceText =
        priceNum != null ? '\$${priceNum.toStringAsFixed(0)}' : '';

        return {
          'id': r['id'],
          'title': r['title'] ?? '',
          'price': priceText,
          'location': r['city'] ?? '',
          'images':
          List<String>.from((r['image_urls'] ?? const <String>[]) as List),
          'postedDate': r['created_at'] ?? '',
          'full': r,
        };
      }).toList();
    }

    // 本地占位数据
    final local = <Map<String, dynamic>>[
      {
        'id': 'm1',
        'title': 'Sample Product 1',
        'price': 120,
        'city': 'Harare',
        'image_urls': ['assets/images/trending_items/item1/1.jpg'],
        'created_at': '2025-08-15T10:00:00Z',
      },
      {
        'id': 'm2',
        'title': 'Sample Product 2',
        'price': 240,
        'city': 'Bulawayo',
        'image_urls': ['assets/images/trending_items/item2/1.jpg'],
        'created_at': '2025-08-14T10:00:00Z',
      },
      {
        'id': 'm3',
        'title': 'Sample Product 3',
        'price': 80,
        'city': 'Mutare',
        'image_urls': ['assets/images/trending_items/item3/1.jpg'],
        'created_at': '2025-08-13T10:00:00Z',
      },
    ];

    final filtered = List<Map<String, dynamic>>.from(local);
    _applySortOnRaw(filtered, widget.sort);

    final start = offset;
    final end = (offset + widget.limit).clamp(0, filtered.length);
    final page = start >= filtered.length
        ? <Map<String, dynamic>>[]
        : filtered.sublist(start, end);

    return page.map<Map<String, dynamic>>((r) {
      final num? priceNum = r['price'] is num ? (r['price'] as num) : null;
      final priceText =
      priceNum != null ? '\$${priceNum.toStringAsFixed(0)}' : '';
      return {
        'id': r['id'],
        'title': r['title'] ?? '',
        'price': priceText,
        'location': r['city'] ?? '',
        'images':
        List<String>.from((r['image_urls'] ?? const <String>[]) as List),
        'postedDate': r['created_at'] ?? '',
        'full': r,
      };
    }).toList();
  }

  /* ---------------- 排序工具 ---------------- */

  void _applySortOnRaw(List<Map<String, dynamic>> rows, String sort) {
    // newest：按 created_at 倒序
    if (sort == 'newest') {
      rows.sort((a, b) {
        DateTime? da = _parseDate(a['created_at']);
        DateTime? db = _parseDate(b['created_at']);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
      return;
    }

    // price_low / price_high：按数值价格
    final asc = sort == 'price_low';
    rows.sort((a, b) {
      final an = _parsePrice(a['price']);
      final bn = _parsePrice(b['price']);
      return asc ? an.compareTo(bn) : bn.compareTo(an);
    });
  }

  num _parsePrice(dynamic v) {
    if (v is num) return v;
    if (v is String) {
      final s = v.replaceAll(RegExp(r'[^\d.]'), '');
      return num.tryParse(s) ?? 0;
    }
    return 0;
  }

  DateTime? _parseDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /* ---------------- 交互 ---------------- */

  void _seeAll() {
    if (widget.categoryId == null) return;
    SafeNavigator.push(
      MaterialPageRoute(
        builder: (_) => CategoryProductsPage(
          categoryId: widget.categoryId!,
          categoryName: widget.title,
        ),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    // 使用集中路由 /listing（navPush: (String routeName, {Object? arguments})）
    await navPush('/listing', arguments: item['id']);
  }

  /* ---------------- UI ---------------- */

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        _content(),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (widget.showSeeAllButton && widget.categoryId != null)
            TextButton(
              onPressed: _seeAll,
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading && _items.isEmpty) {
      return _skeleton();
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text('Load failed: $_error')),
            TextButton(onPressed: _loadInitial, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No ads yet'),
        ),
      );
    }

    return Column(
      children: [
        GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _items.length,
          itemBuilder: (_, i) => _card(_items[i]),
        ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: _loadingMore
                ? const CircularProgressIndicator()
                : TextButton(
              onPressed: _loadMore,
              child: const Text('Load more'),
            ),
          ),
      ],
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final imgs = (p['images'] as List?) ?? [];
    Widget thumb;
    if (imgs.isNotEmpty && imgs.first.toString().startsWith('http')) {
      thumb = Image.network(
        imgs.first,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else if (imgs.isNotEmpty) {
      thumb = Image.asset(
        imgs.first,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      thumb = _placeholder();
    }

    return GestureDetector(
      onTap: () => _openDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
                child: thumb,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p['price']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 12, color: Colors.grey),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          p['location']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _placeholder() => Container(
    color: Colors.grey[300],
    child: const Icon(Icons.image, size: 50, color: Colors.grey),
  );

  Widget _skeleton() => GridView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 0.75,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: 4,
    itemBuilder: (_, __) => Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
          ),
          Container(height: 60, color: Colors.white),
        ],
      ),
    ),
  );
}
