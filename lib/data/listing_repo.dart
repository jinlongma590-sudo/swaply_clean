// lib/data/listing_repo.dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class ListingRepo {
  final _sp = Supabase.instance.client;

  /// 上传图片到 Supabase Storage，返回可公开访问的 URL
  Future<String> uploadImage(Uint8List bytes, {String ext = 'jpg'}) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'items/item_$ts.$ext'; // 存到 bucket:listings 下的 items/ 目录
    await _sp.storage.from('listings').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: 'image/$ext',
          ),
        );
    return _sp.storage.from('listings').getPublicUrl(path);
  }

  /// 写入一条商品数据，返回生成的 id
  Future<String> createListing({
    required String title,
    required num price,
    String? category,
    String? city,
    required String imageUrl,
    String? userId,
  }) async {
    final res = await _sp
        .from('listings')
        .insert({
          'title': title,
          'price': price,
          'category': category,
          'city': city,
          'image_url': imageUrl,
          'user_id': userId, // 现在可以传 null；以后接入登录再填 uid
        })
        .select('id')
        .single();

    return res['id'] as String;
  }

  /// 拉取最新的商品列表
  Future<List<Map<String, dynamic>>> fetchLatest({int limit = 50}) async {
    final res = await _sp
        .from('listings')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res);
  }
}
