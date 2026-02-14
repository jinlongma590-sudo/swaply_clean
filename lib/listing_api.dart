// lib/listing_api.dart —— 兼容你项目 & 旧版 supabase_dart，修复 eq<T> 推断与三元类型提升问题
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ListingApi {
  static final SupabaseClient _sb = Supabase.instance.client;

  /// 与 Supabase Dashboard 保持一致的桶名
  static const String kListingBucket = 'listings';
/* ========================= 工具 ========================= */
  static String _extOf(String p) {
    final i = p.lastIndexOf('.');
    if (i <= 0 || i == p.length - 1) return '';
    return p.substring(i).toLowerCase();
  }

  static Future<void> debugPrintBuckets() async {
    final bs = await _sb.storage.listBuckets();
// ignore: avoid_print
    print('Buckets from client: ${bs.map((b) => b.name).toList()}');
  }

  // 工具：安全把 String 转 int（解析失败返回 null）
  static int? _tryInt(String? s) {
    if (s == null) return null;
    try {
      return int.parse(s);
    } catch (_) {
      return null;
    }
  }

  // 🚨 电话号码清洗：去除非数字，转换本地格式为国际格式
  static String? _cleanPhoneForDb(String? phone) {
    if (phone == null) return null;
    String raw = phone.trim();
    String clean = raw.replaceAll(RegExp(r'[^\d]'), '');

    // A. 如果原始输入带 + 号，信任其区号，仅去除非数字，不触发补齐
    if (raw.startsWith('+')) return clean;

    // B. 津巴布韦 10 位本地格式 (077...) -> 转 26377...
    if (clean.startsWith('0') && clean.length == 10) {
      return '263' + clean.substring(1);
    }

    // C. 津巴布韦 9 位短号格式 (77...) -> 转 26377...
    if (clean.length == 9 && (clean.startsWith('71') || clean.startsWith('77') || clean.startsWith('78'))) {
      return '263' + clean;
    }

    // D. 其他情况保持 10-15 位长度校验
    return (clean.length >= 10 && clean.length <= 15) ? clean : null;
  }

  /// 统一规范化 Supabase 返回：无论是 List 还是 {data: List}
  static List _rowsOf(dynamic resp) {
    if (resp is List) return resp;
    if (resp is Map && resp['data'] is List) {
      return List.from(resp['data'] as List);
    }
    return const <dynamic>[];
  }

/* ========================= 图片上传 ========================= */
  /// 批量上传图片，返回（public）URL 列表。
  /// 若你的桶不是 public，把 getPublicUrl 换成 createSignedUrl。
  static Future<List<String>> uploadListingImages({
    required List<File> files,
    required String userId,
    void Function(int done, int total)? onProgress,
  }) async {
    final urls = <String>[];
    for (int i = 0; i < files.length; i++) {
      final f = files[i];

      var ext = _extOf(f.path);
      if (ext.isEmpty) ext = '.jpg';

      final objectName = '${DateTime.now().millisecondsSinceEpoch}_$i$ext';
      final objectPath = '$userId/$objectName';

      try {
        await _sb.storage.from(kListingBucket).upload(
              objectPath,
              f,
              fileOptions: const FileOptions(upsert: false),
            );

        // public 桶：
        final url = _sb.storage.from(kListingBucket).getPublicUrl(objectPath);

        // 私有桶可改为：
        // final url = await _sb.storage
        //     .from(kListingBucket)
        //     .createSignedUrl(objectPath, 60 * 60 * 24 * 365);

        urls.add(url);
        onProgress?.call(i + 1, files.length);
      } on StorageException catch (e) {
        throw Exception(
          'Upload failed: ${e.message} '
          '(status=${e.statusCode}, bucket=$kListingBucket, path=$objectPath)',
        );
      }
    }

    return urls;
  }

/* ========================= 新增 / 更新 / 删除 ========================= */
  /// 新增一条 listing（兼容旧调用：支持 sellerName / contactPhone / price 为 num?）
  static Future<Map<String, dynamic>> insertListing({
    required String userId,
    required String title,
    num? price, // 兼容页面传入 num?
    String? description,
    String? region,
    String? city,
    String? category,
    List<String>? imageUrls,
    String status = 'active',
    Map<String, dynamic>? attributes,
// 兼容旧参数名（你页面在用）
    String? sellerName,
    String? contactPhone,
// 新参数名（若你后续统一，也可以直接用 phone）
    String? phone,
  }) async {
// 兼容：phone 以 contactPhone 为准，未传则用 phone
    final finalPhone = contactPhone ?? phone;
    // 🚨 入库前清洗电话号码
    final cleanedPhone = _cleanPhoneForDb(finalPhone);
    
    final payload = <String, dynamic>{
      'user_id': userId,
      'title': title,
      'price': price ?? 0, // 避免可空类型导致插入失败
      'description': description,
      'region': region,
      'city': city,
      'category': category,
      'images': imageUrls, // jsonb / text[] 均可
      'status': status,
      'attributes': attributes,
      'seller_name': sellerName, // 若表里没有该列可以删掉
      'phone': cleanedPhone, // 使用清洗后的电话号码
    }..removeWhere((k, v) => v == null);

    print('[POST_AD] payload=$payload'); // ✅ 打印完整 map

    // ✅ 硬校验 price 字段，杜绝 numeric 溢出
    final rawPrice = payload['price'];
    final priceValue = (rawPrice is num) ? rawPrice.toDouble() : double.tryParse('$rawPrice');
    
    if (priceValue == null) {
      throw Exception('Price is invalid: $rawPrice');
    }
    
    // 对应 numeric(12,2) 整数10位上限 (即使现在扩到15位，前端也保持严格校验)
    if (priceValue.abs() >= 10000000000) { // 10^10
      throw Exception('Price too large: $priceValue');
    }
    
    payload['price'] = priceValue;

    final data = await _sb.from('listings').insert(payload).select().single();
    return Map<String, dynamic>.from(data);
  }

  // ✅ 修改：支持 String 类型 ID（UUID）
  static Future<Map<String, dynamic>> updateListing({
    required String id, // ✅ 改为 String
    Map<String, dynamic>? fields,
  }) async {
    final dataToUpdate = Map<String, dynamic>.from(fields ?? {})
      ..removeWhere((k, v) => v == null);

    // ✅ 清洗电话号码字段（如果更新中包含 phone）
    if (dataToUpdate.containsKey('phone')) {
      final cleanedPhone = _cleanPhoneForDb(dataToUpdate['phone']);
      dataToUpdate['phone'] = cleanedPhone;
      if (cleanedPhone == null) {
        dataToUpdate.remove('phone');
      }
    }

    // ✅ 硬校验 price 字段，杜绝 numeric 溢出（如果更新中包含 price）
    if (dataToUpdate.containsKey('price')) {
      final rawPrice = dataToUpdate['price'];
      final priceValue = (rawPrice is num) ? rawPrice.toDouble() : double.tryParse('$rawPrice');
      
      if (priceValue == null) {
        throw Exception('Price is invalid: $rawPrice');
      }
      
      // 对应 numeric(12,2) 整数10位上限 (即使现在扩到15位，前端也保持严格校验)
      if (priceValue.abs() >= 10000000000) { // 10^10
        throw Exception('Price too large: $priceValue');
      }
      
      dataToUpdate['price'] = priceValue;
    }

    final data = await _sb
        .from('listings')
        .update(dataToUpdate)
        .eq('id', id)
        .select()
        .single();

    return Map<String, dynamic>.from(data);
  }

  // ✅ 修改：支持 String 类型 ID（UUID）
  static Future<void> deleteListing({
    required String id, // ✅ 改为 String
    List<String>? storageObjectPaths,
  }) async {
    await _sb.from('listings').delete().eq('id', id);
    if (storageObjectPaths != null && storageObjectPaths.isNotEmpty) {
      try {
        await _sb.storage.from(kListingBucket).remove(storageObjectPaths);
      } catch (_) {
        // 忽略存储删除失败
      }
    }
  }

/* ========================= 查询 / 搜索 / 计数 ========================= */
  /// 列表查询（分页/筛选/排序）
  /// - 正式参数：categoryId
  /// - 兼容参数：category(int 或 String)、userId、sort
  static Future<List<Map<String, dynamic>>> fetchListings({
    String? city,
// ===== 正式参数 =====
    int? categoryId,

// ===== 兼容旧调用的别名参数（不要删）=====
    dynamic category, // 旧：可能是 String 或 int
    String? userId, // 旧
    String? sort, // 旧：'newest' | 'price_low' | 'price_high'

// ===== 其余参数 =====
    required int limit,
    required int offset,
    String orderBy = 'created_at',
    bool ascending = false,
    String? status,

// 若实现了内存缓存，可用于强制绕过缓存
    bool forceNetwork = false,
  }) async {
// ---------- 兼容映射 ----------
    int? catId = categoryId;
    String? catString;
    if (catId == null && category != null) {
      if (category is int) {
        catId = category;
      } else if (category is String && category.isNotEmpty) {
        catString = category;
      }
    }
// 如果传来字符串其实是数字，自动转成 id
    if (catId == null && catString != null) {
      final p = _tryInt(catString);
      if (p != null) {
        catId = p;
        catString = null;
      }
    }

// 兼容 sort 语义
    String orderBy0 = orderBy;
    bool asc = ascending;
    if (sort != null) {
      if (sort == 'price_low') {
        orderBy0 = 'price';
        asc = true;
      } else if (sort == 'price_high') {
        orderBy0 = 'price';
        asc = false;
      } else {
        orderBy0 = 'created_at';
        asc = false;
      }
    }

    if (forceNetwork) {
      // 这里可清除你的内存缓存
    }

// ---------- 查询 ----------
    dynamic query = _sb.from('listings').select('*');

    if (status != null) query = query.eq('status', status);
    if (city != null && city.isNotEmpty) query = query.eq('city', city);

// ✅ 避免 eq<T> 的 int/string 泛型推断问题：统一用 filter('col','eq',value)
    final dynamic cat = (catId != null) ? catId : catString;
    if (cat != null) {
      if (cat is num) {
        query = query.filter('category_id', 'eq', cat);
      } else {
        query = query.filter('category', 'eq', cat.toString());
      }
    }

    if (userId != null && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    }

    query = query.order(orderBy0, ascending: asc).range(
          offset,
          offset + limit - 1,
        );

    final resp = await query;
    final rows = _rowsOf(resp);

    return rows
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 关键词搜索（简单 ilike），并兼容 category 既可能是 id 也可能是 name
  static Future<List<Map<String, dynamic>>> searchListings({
    required String keyword,
    int limit = 20,
    int offset = 0,
    String? region,
    String? city,
    String? category,
    String? status = 'active',
    String orderBy = 'created_at',
    bool ascending = false,
  }) async {
    dynamic query = _sb.from('listings').select('*');
    if (status != null) query = query.eq('status', status);
    if (region != null && region.isNotEmpty) query = query.eq('region', region);
    if (city != null && city.isNotEmpty) query = query.eq('city', city);

// ✅ 同样用 filter 避免泛型冲突
    if (category != null && category.isNotEmpty) {
      final catId = int.tryParse(category);
      if (catId != null) {
        query = query.filter('category_id', 'eq', catId);
      } else {
        query = query.filter('category', 'eq', category.toString());
      }
    }

    query = query.or('title.ilike.%$keyword%,description.ilike.%$keyword%');
    query = query.order(orderBy, ascending: ascending).range(
          offset,
          offset + limit - 1,
        );

    final resp = await query;
    final rows = _rowsOf(resp);

    return rows
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 计数（兼容最旧版 SDK：不再使用 select(count: ...)）
  static Future<int> countListings({
    String? region,
    String? city,
    String? category,
    String? status = 'active',
    String? userId,
  }) async {
    dynamic query = _sb.from('listings').select('id');
    if (status != null) query = query.eq('status', status);
    if (region != null && region.isNotEmpty) query = query.eq('region', region);
    if (city != null && city.isNotEmpty) query = query.eq('city', city);

// ✅ 用 filter 来兼容 int / String
    if (category != null && category.isNotEmpty) {
      final catId = int.tryParse(category);
      if (catId != null) {
        query = query.filter('category_id', 'eq', catId);
      } else {
        query = query.filter('category', 'eq', category.toString());
      }
    }

    if (userId != null && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    }

    final resp = await query;
    final rows = _rowsOf(resp);
    return rows.length;
  }

/* ========================= 维表/下拉（统一 _rowsOf 版本） ========================= */
  static Future<List<String>> getRegions({String status = 'active'}) async {
    final resp =
        await _sb.from('listings').select('region').eq('status', status);
    final rows = _rowsOf(resp);
    final set = <String>{};
    for (final row in rows) {
      final v = (row as Map)['region'];
      if (v != null && v.toString().isNotEmpty) set.add(v.toString());
    }
    final list = set.toList()..sort();
    return list;
  }

  static Future<List<String>> getCities({String status = 'active'}) async {
    final resp = await _sb.from('listings').select('city').eq('status', status);
    final rows = _rowsOf(resp);
    final set = <String>{};
    for (final row in rows) {
      final v = (row as Map)['city'];
      if (v != null && v.toString().isNotEmpty) set.add(v.toString());
    }
    final list = set.toList()..sort();
    return list;
  }
}
