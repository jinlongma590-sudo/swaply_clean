// lib/models/listing_store.dart
class ListingStore {
  // 单例模式
  static final ListingStore _instance = ListingStore._internal();
  static ListingStore get i => _instance;

  ListingStore._internal();

  // 存储所有列表数据
  final List<Map<String, dynamic>> _listings = [];

  // 添加新的listing
  void add(Map<String, dynamic> listing) {
    _listings.add(listing);
  }

  // 获取所有listings
  List<Map<String, dynamic>> getAll() {
    return List.from(_listings); // 返回副本，避免外部直接修改
  }

  // 根据ID查找单个listing (find方法)
  Map<String, dynamic>? find(String id) {
    try {
      return _listings.firstWhere((item) => item['id'] == id);
    } catch (e) {
      return null;
    }
  }

  // 根据ID获取单个listing (与find方法相同，为了兼容性保留)
  Map<String, dynamic>? getById(String id) {
    return find(id);
  }

  // 根据ID删除listing
  void remove(String id) {
    _listings.removeWhere((item) => item['id'] == id);
  }

  // 更新listing
  void update(String id, Map<String, dynamic> updatedListing) {
    final index = _listings.indexWhere((item) => item['id'] == id);
    if (index != -1) {
      _listings[index] = updatedListing;
    }
  }

  // 清空所有listings
  void clear() {
    _listings.clear();
  }

  // 获取listings数量
  int get count => _listings.length;

  // 根据分类获取listings
  List<Map<String, dynamic>> getByCategory(String category) {
    return _listings.where((item) => item['category'] == category).toList();
  }

  // 根据用户获取listings（假设有sellerName字段）
  List<Map<String, dynamic>> getBySeller(String sellerName) {
    return _listings.where((item) => item['sellerName'] == sellerName).toList();
  }

  // 搜索功能
  List<Map<String, dynamic>> search(String query) {
    final lowerQuery = query.toLowerCase();
    return _listings.where((item) {
      final title = (item['title'] ?? '').toString().toLowerCase();
      final description = (item['description'] ?? '').toString().toLowerCase();
      final category = (item['category'] ?? '').toString().toLowerCase();

      return title.contains(lowerQuery) ||
          description.contains(lowerQuery) ||
          category.contains(lowerQuery);
    }).toList();
  }

  // 获取最近的listings（按日期排序）
  List<Map<String, dynamic>> getRecent({int limit = 10}) {
    final sorted = List<Map<String, dynamic>>.from(_listings);
    sorted.sort((a, b) {
      final dateA = DateTime.tryParse(a['postedDate'] ?? '') ?? DateTime(1970);
      final dateB = DateTime.tryParse(b['postedDate'] ?? '') ?? DateTime(1970);
      return dateB.compareTo(dateA); // 降序排列，最新的在前
    });

    return sorted.take(limit).toList();
  }

  // 检查是否存在某个ID的listing
  bool exists(String id) {
    return _listings.any((item) => item['id'] == id);
  }
}
