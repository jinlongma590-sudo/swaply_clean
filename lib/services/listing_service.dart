// lib/services/listing_service.dart
//
// 说明：这是对 listing_api.dart 的薄封装，统一前端调用口，便于在
//  页面（Profile/My Listings/Category/Search）中直接复用。
//  - 兼容你的表结构：images(json/array)、seller_name、phone、city/category 等
//  - 提供删除时"顺带删存储对象"的安全方法
//  - 提供常用查询/计数/搜索
//
// 依赖：
//   import 'package:swaply/listing_api.dart';  // 你的 ListingApi（已对齐桶名 'listing'）
//   import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/listing_api.dart';

class ListingService {
  static final SupabaseClient _sb = Supabase.instance.client;

  /// 统一读取 images 字段（兼容未来可能的 image_urls）
  static List<String> readImages(Map<String, dynamic> row) {
    final a = row['images'];
    if (a is List) return a.map((e) => e.toString()).toList();
    final b = row['image_urls'];
    if (b is List) return b.map((e) => e.toString()).toList();
    return const <String>[];
  }

  /// 创建 listing：先上传图片（可选），再插入表
  static Future<Map<String, dynamic>> createListing({
    required String userId,
    required String title,
    required num price,
    String? description,
    String? region,
    required String city,
    required String category,
    List<File>? imageFiles,
    List<String>? imageUrls, // 如果外部已上传好，直接传 URL
    String? sellerName,
    String? contactPhone,
    Map<String, dynamic>? attributes,
    String status = 'active',
    void Function(int done, int total)? onUploadProgress,
  }) async {
    List<String> finalUrls = imageUrls ?? const [];

    // 如需先上传
    if ((imageFiles != null) && imageFiles.isNotEmpty) {
      finalUrls = await ListingApi.uploadListingImages(
        files: imageFiles,
        userId: userId,
        onProgress: onUploadProgress,
      );
    }

    final row = await ListingApi.insertListing(
      userId: userId,
      title: title,
      price: price,
      description: description,
      region: region,
      city: city,
      category: category,
      imageUrls: finalUrls,
      sellerName: sellerName,
      contactPhone: contactPhone,
      attributes: attributes,
      status: status,
    );

    return row;
  }

  /// 更新 listing（只传需要更新的字段）
  static Future<Map<String, dynamic>> updateListingFields({
    required String id, // ✅ String 类型（支持 UUID）
    String? title,
    num? price,
    String? description,
    String? region,
    String? city,
    String? category,
    List<String>? images, // 直接覆写 images 列
    String? sellerName,
    String? phone, // 或 contactPhone
    Map<String, dynamic>? attributes,
    String? status,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'price': price,
      'description': description,
      'region': region,
      'city': city,
      'category': category,
      'images': images,
      'seller_name': sellerName,
      'phone': phone,
      'attributes': attributes,
      'status': status,
    }..removeWhere((k, v) => v == null);

    return ListingApi.updateListing(id: id, fields: data);
  }

  /// 删除 listing，尽量把存储里的对象也删掉（容错）
  static Future<void> deleteListingAndStorage({
    required String id, // ✅ String 类型（支持 UUID）
    List<String>? imageObjectPaths, // 如果你保存的是 public URL，需要先转成对象 path 再传入
  }) async {
    await ListingApi.deleteListing(
        id: id, storageObjectPaths: imageObjectPaths);
  }

  /// 根据用户拉取我的广告（分页）
  static Future<List<Map<String, dynamic>>> fetchMyListings({
    required String userId,
    int limit = 24,
    int offset = 0,
    String orderBy = 'created_at',
    bool ascending = false,
    String status = 'active',
  }) {
    return ListingApi.fetchListings(
      userId: userId,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      ascending: ascending,
      status: status,
    );
  }

  /// 统计我的广告数
  static Future<int> countMyListings({
    required String userId,
    String status = 'active',
  }) {
    return ListingApi.countListings(userId: userId, status: status);
  }

  /// 分类 + 城市筛选的分页查询（列表页/分类页使用）
  static Future<List<Map<String, dynamic>>> fetchByCategoryCity({
    required String category,
    String? city, // null 表示 All Zimbabwe
    int limit = 24,
    int offset = 0,
    String sort = 'newest', // newest | price_low | price_high
  }) async {
    String orderBy = 'created_at';
    bool ascending = false;

    switch (sort) {
      case 'price_low':
        orderBy = 'price';
        ascending = true;
        break;
      case 'price_high':
        orderBy = 'price';
        ascending = false;
        break;
      default:
        orderBy = 'created_at';
        ascending = false;
    }

    return ListingApi.fetchListings(
      category: category,
      city: city,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      ascending: ascending,
      status: 'active',
    );
  }

  /// 真实计数（分类+城市）
  static Future<int> countByCategoryCity({
    required String category,
    String? city,
  }) {
    return ListingApi.countListings(
      category: category,
      city: city,
      status: 'active',
    );
  }

  /// 关键字搜索（按城市/分类可选）
  static Future<List<Map<String, dynamic>>> search({
    required String keyword,
    String? city,
    String? category,
    int limit = 50,
    int offset = 0,
  }) {
    return ListingApi.searchListings(
      keyword: keyword,
      city: city,
      category: category,
      limit: limit,
      offset: offset,
      orderBy: 'created_at',
      ascending: false,
      status: 'active',
    );
  }

  /// 把 public URL 转为 Storage 对象路径（如果你需要在删除时 remove 对象）
  ///
  /// 例：
  ///   publicUrl: https://xyz.supabase.co/storage/v1/object/public/listing/<userId>/<fileName>.jpg
  ///   -> objectPath: <userId>/<fileName>.jpg
  static String? publicUrlToObjectPath(String? publicUrl) {
    if (publicUrl == null || publicUrl.isEmpty) return null;
    // 简单切割，找到 "/object/public/" 后面的部分
    final idx = publicUrl.indexOf('/object/public/');
    if (idx < 0) return null;
    final rest = publicUrl.substring(idx + '/object/public/'.length);
    // rest 格式: "<bucket>/<objectPath>"
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    // final bucket = rest.substring(0, slash); // 如需校验桶名可用
    final objectPath = rest.substring(slash + 1);
    return objectPath;
  }
}
