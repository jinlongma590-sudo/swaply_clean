// lib/services/favorites_update_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class FavoritesUpdateService {
  static final FavoritesUpdateService _instance =
      FavoritesUpdateService._internal();
  factory FavoritesUpdateService() => _instance;
  FavoritesUpdateService._internal();

  // 用于通知收藏状态改变的流控制器
  final StreamController<FavoriteUpdateEvent> _favoritesController =
      StreamController<FavoriteUpdateEvent>.broadcast();

  // 获取收藏更新流
  Stream<FavoriteUpdateEvent> get favoritesStream =>
      _favoritesController.stream;

  // 通知收藏状态改变
  void notifyFavoriteChanged({
    required String listingId,
    required bool isAdded,
    Map<String, dynamic>? listingData,
  }) {
    if (!_favoritesController.isClosed) {
      _favoritesController.add(FavoriteUpdateEvent(
        listingId: listingId,
        isAdded: isAdded,
        listingData: listingData,
      ));

      if (kDebugMode) {
        print('Favorite update notification sent: $listingId, added: $isAdded');
      }
    }
  }

  // 清理资源
  void dispose() {
    _favoritesController.close();
  }
}

// 收藏更新事件类
class FavoriteUpdateEvent {
  final String listingId;
  final bool isAdded; // true: 添加到收藏, false: 从收藏移除
  final Map<String, dynamic>? listingData; // 商品数据（用于添加时）

  FavoriteUpdateEvent({
    required this.listingId,
    required this.isAdded,
    this.listingData,
  });
}
