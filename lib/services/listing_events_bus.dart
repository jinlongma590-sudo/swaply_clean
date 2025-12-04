// lib/services/listing_events_bus.dart
import 'dart:async';

/// 发布成功事件（可带新商品ID，便于首页做插入动画/定位）
class ListingPublishedEvent {
  final String? listingId;
  ListingPublishedEvent([this.listingId]);
}

/// 资料更新事件（编辑资料页成功后发出，用于其他页面强制刷新）
class ProfileUpdatedEvent {
  final String userId;
  ProfileUpdatedEvent(this.userId);
}

/// 轻量全局事件总线：统一“实例”写法，避免静态/实例重名冲突
class ListingEventsBus {
  ListingEventsBus._();
  static final ListingEventsBus instance = ListingEventsBus._();

  final _controller = StreamController<dynamic>.broadcast();

  /// 外部只读流（各页面订阅）
  Stream<dynamic> get stream => _controller.stream;

  /// 通用广播
  void emit(dynamic event) => _controller.add(event);

  /// 发布商品结束后广播
  void emitPublished([String? listingId]) =>
      _controller.add(ListingPublishedEvent(listingId));

  /// 关闭（一般不需要调用）
  Future<void> dispose() async {
    await _controller.close();
  }
}
