// lib/services/message_service.dart - 稳定精简版（RPC+视图优先+无重复通知）

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
// 如果你需要本地系统通知（不入库），可在回调里自行触发；此处不再主动写 notifications，避免与触发器重复
// import 'notification_service.dart';

/// 消息服务类 - 处理与 offer 相关的对话消息
class MessageService {
  static final SupabaseClient _client = Supabase.instance.client;

  static const String _tableName = 'offer_messages';
  // 如果已建视图：offer_messages_with_profiles（推荐），会优先使用
  static const String _viewName = 'offer_messages_with_profiles';

  /// 获取当前用户ID
  static String? get _currentUserId => _client.auth.currentUser?.id;

  /// 调试打印
  static void _debugPrint(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[MessageService] $message');
    }
  }

  /// 安全地将 offer ID 转换为整数
  static int? _parseOfferId(dynamic offerId) {
    try {
      if (offerId == null) {
        _debugPrint('offerId为空');
        return null;
      }
      if (offerId is int) {
        _debugPrint('offerId已经是整数: $offerId');
        return offerId > 0 ? offerId : null;
      }
      if (offerId is String) {
        _debugPrint('转换字符串offerId: "$offerId"');
        final trimmed = offerId.trim();
        if (trimmed.isEmpty) {
          _debugPrint('offerId字符串为空');
          return null;
        }
        final parsed = int.tryParse(trimmed);
        if (parsed != null && parsed > 0) {
          _debugPrint('转换成功: $parsed');
          return parsed;
        } else {
          _debugPrint('转换失败或数值无效: $trimmed');
          return null;
        }
      }
      final stringValue = offerId.toString().trim();
      if (stringValue.isEmpty || stringValue == 'null') {
        _debugPrint('转换后的字符串无效: "$stringValue"');
        return null;
      }
      final parsed = int.tryParse(stringValue);
      if (parsed != null && parsed > 0) {
        _debugPrint('其他类型转换成功: $parsed');
        return parsed;
      } else {
        _debugPrint('其他类型转换失败: "$stringValue"');
        return null;
      }
    } catch (e) {
      _debugPrint('offerId转换异常: $e');
      return null;
    }
  }

  /// 发送消息（仅 RPC v2：jsonb 单参）
  static Future<Map<String, dynamic>?> sendMessage({
    required String offerId,
    required String receiverId,
    required String message,
    String messageType = 'text',
  }) async {
    try {
      final senderId = _currentUserId;
      if (senderId == null) {
        _debugPrint('未找到已认证用户');
        return null;
      }
      if (offerId.isEmpty || receiverId.isEmpty || message.trim().isEmpty) {
        _debugPrint(
            '参数无效: offerId=$offerId, receiverId=$receiverId, message长度=${message.length}');
        return null;
      }

      _debugPrint('=== 开始发送消息（RPC v2） ===');
      _debugPrint('原始参数 - offerId: "$offerId", receiverId: "$receiverId"');
      _debugPrint(
          '消息内容: "${message.substring(0, message.length.clamp(0, 50))}${message.length > 50 ? '...' : ''}"');

      final offerIdInt = _parseOfferId(offerId);
      if (offerIdInt == null) {
        _debugPrint('错误: 无法解析offerId: "$offerId"');
        return null;
      }

      // 仅传一个 jsonb 参数，交由函数内部强转
      final result = await _client.rpc('send_offer_message_v2', params: {
        'p_data': {
          'offer_id': offerId.toString(), // 传字符串由函数内部 ::bigint
          'sender_id': senderId, // uuid
          'receiver_id': receiverId, // uuid
          'message': message.trim(),
          'message_type': messageType, // 'text' / 'system'
        }
      });

      if (result == null) {
        _debugPrint('RPC返回为空');
        return null;
      }

      final messageData = Map<String, dynamic>.from(result);
      _debugPrint('RPC v2 插入成功: ${messageData['id']}');

      // 数据库触发器已自动写 notifications，这里避免重复造通知
      return messageData;
    } catch (e) {
      _debugPrint('发送消息(RPC v2)异常: $e');
      if (e is PostgrestException) {
        _debugPrint(
            'PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
      }
      return null;
    }
  }

  /// 获取 offer 的所有消息（视图优先，其次表 + 手动补资料）
  static Future<List<Map<String, dynamic>>> getOfferMessages({
    required String offerId,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      _debugPrint('获取offer消息: $offerId');

      final offerIdInt = _parseOfferId(offerId);
      if (offerIdInt == null) {
        _debugPrint('无效的offer ID格式: $offerId');
        return [];
      }

      // 1) 先尝试视图（推荐你建好该视图）
      try {
        final List<dynamic> messagesFromView = await _client
            .from(_viewName)
            .select('*')
            .eq('offer_id', offerIdInt)
            .order('created_at', ascending: true)
            .range(offset, offset + limit - 1);

        _debugPrint('视图查询成功，返回 ${messagesFromView.length} 条');
        return messagesFromView
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (viewErr) {
        _debugPrint('视图查询失败，回退到表查询: $viewErr');
      }

      // 2) 回退到表 + 手动补 profiles
      final List<dynamic> messages = await _client
          .from(_tableName)
          .select('*')
          .eq('offer_id', offerIdInt)
          .order('created_at', ascending: true)
          .range(offset, offset + limit - 1);

      final enriched = <Map<String, dynamic>>[];
      for (final m in messages) {
        final map = Map<String, dynamic>.from(m);

        // 发送者资料
        try {
          final sid = map['sender_id'];
          if (sid != null) {
            final p = await _client
                .from('profiles')
                .select('full_name, avatar_url')
                .eq('id', sid)
                .maybeSingle();
            if (p != null) map['sender_profiles'] = p;
          }
        } catch (e) {
          _debugPrint('获取发送者资料出错: $e');
        }

        // 接收者资料
        try {
          final rid = map['receiver_id'];
          if (rid != null) {
            final p = await _client
                .from('profiles')
                .select('full_name, avatar_url')
                .eq('id', rid)
                .maybeSingle();
            if (p != null) map['receiver_profiles'] = p;
          }
        } catch (e) {
          _debugPrint('获取接收者资料出错: $e');
        }

        enriched.add(map);
      }

      _debugPrint('表查询+补资料成功获取 ${enriched.length} 条消息');
      return enriched;
    } catch (e) {
      _debugPrint('获取消息时出错: $e');
      return [];
    }
  }

  /// 订阅实时消息（仅用来刷新 & 可在回调里做本地提示）
  static RealtimeChannel subscribeToOfferMessages({
    required String offerId,
    required Function(Map<String, dynamic>) onMessageReceived,
  }) {
    _debugPrint('订阅offer消息: $offerId');

    final offerIdInt = _parseOfferId(offerId);
    if (offerIdInt == null) {
      _debugPrint('无效的offer ID格式，无法订阅: $offerId');
      return _client
          .channel('empty_channel_${DateTime.now().millisecondsSinceEpoch}');
    }

    _debugPrint('转换字符串offerId: "$offerId"');
    _debugPrint('转换结果: $offerIdInt');

    final channel = _client
        .channel(
            'offer_messages:$offerId:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _tableName,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'offer_id',
            value: offerIdInt,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            final messageData = Map<String, dynamic>.from(record);
            _debugPrint('通过实时连接收到新消息: ${messageData['message']}');

            // 仅在前端需要时触发“本地提示”；入库通知已由 DB 触发器完成
            onMessageReceived(messageData);
                    },
        )
        .subscribe();

    _debugPrint('实时订阅创建成功: $offerId');
    return channel;
  }

  /// 标记消息为已读
  static Future<bool> markMessagesAsRead({
    required String offerId,
    String? receiverId,
  }) async {
    try {
      final userId = receiverId ?? _currentUserId;
      if (userId == null) return false;

      final offerIdInt = _parseOfferId(offerId);
      if (offerIdInt == null) {
        _debugPrint('无效的offer ID格式: $offerId');
        return false;
      }

      _debugPrint('标记消息为已读: offer $offerId');

      await _client
          .from(_tableName)
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('offer_id', offerIdInt)
          .eq('receiver_id', userId)
          .eq('is_read', false);

      _debugPrint('消息已标记为已读');
      return true;
    } catch (e) {
      _debugPrint('标记消息已读时出错: $e');
      return false;
    }
  }

  /// 获取未读消息数量
  static Future<int> getUnreadMessageCount({
    required String offerId,
    String? userId,
  }) async {
    try {
      final targetUserId = userId ?? _currentUserId;
      if (targetUserId == null) return 0;

      final offerIdInt = _parseOfferId(offerId);
      if (offerIdInt == null) {
        _debugPrint('无效的offer ID格式: $offerId');
        return 0;
      }

      final List<dynamic> data = await _client
          .from(_tableName)
          .select('id')
          .eq('offer_id', offerIdInt)
          .eq('receiver_id', targetUserId)
          .eq('is_read', false);

      return data.length;
    } catch (e) {
      _debugPrint('获取未读消息数量时出错: $e');
      return 0;
    }
  }

  /// 创建系统消息
  static Future<bool> createSystemMessage({
    required String offerId,
    required String receiverId,
    required String message,
  }) async {
    try {
      final result = await sendMessage(
        offerId: offerId,
        receiverId: receiverId,
        message: message,
        messageType: 'system',
      );
      return result != null;
    } catch (e) {
      _debugPrint('创建系统消息时出错: $e');
      return false;
    }
  }

  /// 取消订阅消息
  static void unsubscribeFromMessages(RealtimeChannel channel) {
    _debugPrint('取消订阅消息');
    try {
      _client.removeChannel(channel);
    } catch (e) {
      _debugPrint('取消订阅时出错: $e');
    }
  }

  /// 删除消息记录（只能删除自己的）
  static Future<bool> deleteMessage(String messageId) async {
    try {
      final userId = _currentUserId;
      if (userId == null) return false;

      _debugPrint('删除消息: $messageId');

      await _client
          .from(_tableName)
          .delete()
          .eq('id', messageId)
          .eq('sender_id', userId);

      _debugPrint('消息删除成功');
      return true;
    } catch (e) {
      _debugPrint('删除消息时出错: $e');
      return false;
    }
  }

  /// 测试连接
  static Future<bool> testConnection() async {
    try {
      _debugPrint('测试消息服务连接...');
      final userId = _currentUserId;
      if (userId == null) {
        _debugPrint('连接测试时无当前用户');
        return false;
      }
      await _client.from(_tableName).select('id').limit(1);
      _debugPrint('消息服务连接测试成功');
      return true;
    } catch (e) {
      _debugPrint('消息服务连接测试失败: $e');
      return false;
    }
  }

  /// 调试方法：测试 offer_id 类型转换
  static void debugOfferIdConversion(dynamic testOfferId) {
    _debugPrint('=== 调试Offer ID转换 ===');
    _debugPrint('输入值: $testOfferId');
    _debugPrint('输入类型: ${testOfferId.runtimeType}');

    final converted = _parseOfferId(testOfferId);
    _debugPrint('转换结果: $converted');
    _debugPrint('转换后类型: ${converted.runtimeType}');
    _debugPrint('=== 调试结束 ===');
  }

  /// 获取简化的消息列表
  static Future<List<Map<String, dynamic>>> getSimpleOfferMessages({
    required String offerId,
    int limit = 100,
  }) async {
    try {
      _debugPrint('获取简化消息列表: $offerId');

      final offerIdInt = _parseOfferId(offerId);
      if (offerIdInt == null) {
        _debugPrint('无效的offer ID格式: $offerId');
        return [];
      }

      final List<dynamic> messages = await _client
          .from(_tableName)
          .select('*')
          .eq('offer_id', offerIdInt)
          .order('created_at', ascending: true)
          .limit(limit);

      return messages
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      _debugPrint('获取简化消息时出错: $e');
      return [];
    }
  }

  /// 批量标记消息为已读
  static Future<bool> markMultipleMessagesAsRead({
    required List<String> messageIds,
  }) async {
    try {
      final userId = _currentUserId;
      if (userId == null || messageIds.isEmpty) return false;

      _debugPrint('批量标记${messageIds.length}条消息为已读');

      await _client
          .from(_tableName)
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .filter('id', 'in', '(${messageIds.join(',')})')
          .eq('receiver_id', userId);

      return true;
    } catch (e) {
      _debugPrint('批量标记消息已读时出错: $e');
      return false;
    }
  }

  /// 检查消息发送/进入会话权限（前端门禁；真正的读写由 RLS 负责）
  static Future<bool> canSendMessage({
    required String offerId,
    required String receiverId, // 可能是“对方”的 id，也可能是“自己”的 id
  }) async {
    try {
      final uid = _currentUserId;
      if (uid == null) return false;

      final offerIdInt = _parseOfferId(offerId);
      if (offerIdInt == null) return false;

      final offer = await _client
          .from('offers')
          .select('user_id')
          .eq('id', offerIdInt)
          .maybeSingle();
      if (offer == null) return false;

      final ownerId = offer['user_id'] as String?;

      // 放行条件（任一成立即可）：
      // 1) 当前用户就是 offer 拥有者
      // 2) 传入的 receiverId 是 offer 拥有者（即把“对方”传进来时，对方=owner 也放行）
      // 3) 当前用户就是传入的 receiverId（把“自己”传进来也放行）
      final allowed =
          (uid == ownerId) || (receiverId == ownerId) || (uid == receiverId);

      if (!allowed) {
        _debugPrint('用户无权限进入会话（前端门禁拦截）');
      }
      return allowed;
    } catch (e) {
      _debugPrint('检查发送权限时出错: $e');
      return false;
    }
  }
}
