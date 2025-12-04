// lib/utils/share_utils.dart
import 'dart:io';
import 'package:flutter/foundation.dart'; // ✅ 添加：用于 kDebugMode
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareUtils {
  static Future<void> _openExternal(Uri uri) async {
    if (kDebugMode) {
      print('📱 [ShareUtils] Launching external: $uri');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      if (kDebugMode) {
        print('🔍 [ShareUtils] Checking if can launch: $uri');
      }

      if (await canLaunchUrl(uri)) {
        await _openExternal(uri);
        if (kDebugMode) {
          print('✅ [ShareUtils] Successfully launched: $uri');
        }
        return true;
      }

      if (kDebugMode) {
        print('⚠️ [ShareUtils] Cannot launch: $uri');
      }
      return false;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [ShareUtils] Error launching $uri: $e');
        print('Stack trace: $stackTrace');
      }
      return false;
    }
  }

  /// ✅ WhatsApp：优先尝试普通版，其次 Business 版；未安装→跳商店（Android→Play / iOS→App Store）
  /// 最终兜底：复制消息到剪贴板
  static Future<void> toWhatsApp({required String text}) async {
    if (kDebugMode) {
      print('📱 [ShareUtils] Attempting WhatsApp share');
    }

    final encoded = Uri.encodeComponent(text);

    // ① 尝试普通版
    final wa = Uri.parse('whatsapp://send?text=$encoded');
    if (await _tryLaunch(wa)) return;

    // ② iOS 上可能只有 Business 版
    final waBiz = Uri.parse('whatsapp-business://send?text=$encoded');
    if (await _tryLaunch(waBiz)) return;

    // ③ 商店回退
    if (Platform.isAndroid) {
      // Android：优先 market:// 深链接
      final market = Uri.parse('market://details?id=com.whatsapp');
      if (await _tryLaunch(market)) return;

      // 备用：Play Store 网页版
      final playWeb = Uri.parse(
          'https://play.google.com/store/apps/details?id=com.whatsapp');
      if (await _tryLaunch(playWeb)) return;
    } else if (Platform.isIOS) {
      // iOS：App Store（支持 https 和 itms-apps 两种）
      final appStore = Uri.parse('https://apps.apple.com/app/id310633997');
      if (await _tryLaunch(appStore)) return;

      // 备用：itms-apps 协议
      final itms = Uri.parse('itms-apps://apps.apple.com/app/id310633997');
      if (await _tryLaunch(itms)) return;
    }

    // ④ 兜底：复制到剪贴板
    if (kDebugMode) {
      print('📋 [ShareUtils] WhatsApp not available, copying to clipboard');
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// ✅ Telegram：优先 share?url=...&text=...；不含 url 时走 msg?text=...
  /// 未安装→商店（Android→Play / iOS→App Store）
  /// 最终兜底：复制链接
  static Future<void> toTelegram({String? url, String? text}) async {
    if (kDebugMode) {
      print('📱 [ShareUtils] Attempting Telegram share');
      print('   URL: $url');
      print('   Text: $text');
    }

    final hasUrl = (url != null && url.isNotEmpty);
    final u = hasUrl ? Uri.encodeComponent(url) : null;
    final t = (text != null && text.isNotEmpty)
        ? Uri.encodeComponent(text)
        : null;

    // ① 先用 share?url=...&text=...
    // ✅ 关键：Telegram 的 share 协议格式
    if (hasUrl) {
      final tgShare = Uri.parse(
          'tg://share?url=$u${t != null ? '&text=$t' : ''}');
      if (await _tryLaunch(tgShare)) return;
    }

    // ② 退化到 msg?text=...
    if (t != null) {
      final tgMsg = Uri.parse('tg://msg?text=$t');
      if (await _tryLaunch(tgMsg)) return;
    }

    // ③ 尝试网页版（会提示打开 Telegram App）
    if (hasUrl) {
      final webShare = Uri.parse(
          'https://t.me/share/url?url=$u${t != null ? '&text=$t' : ''}');
      if (await _tryLaunch(webShare)) return;
    }

    // ④ 商店回退
    if (kDebugMode) {
      print('⚠️ [ShareUtils] Telegram not available, trying store');
    }

    if (Platform.isAndroid) {
      // Android：优先 market:// 深链接
      final market = Uri.parse('market://details?id=org.telegram.messenger');
      if (await _tryLaunch(market)) return;

      // 备用：Play Store 网页版
      final playWeb = Uri.parse(
          'https://play.google.com/store/apps/details?id=org.telegram.messenger');
      if (await _tryLaunch(playWeb)) return;
    } else if (Platform.isIOS) {
      // iOS：App Store
      final appStore = Uri.parse('https://apps.apple.com/app/id686449807');
      if (await _tryLaunch(appStore)) return;

      // 备用：itms-apps 协议
      final itms = Uri.parse('itms-apps://apps.apple.com/app/id686449807');
      if (await _tryLaunch(itms)) return;
    }

    // ⑤ 兜底：复制链接
    final fallbackText = url ?? text ?? '';
    if (fallbackText.isNotEmpty) {
      if (kDebugMode) {
        print('📋 [ShareUtils] Copying to clipboard as fallback');
      }
      await Clipboard.setData(ClipboardData(text: fallbackText));
    }
  }

  /// ✅ Facebook：尝试用 fb://facewebmodal 拉起 App，不成就走网页分享
  /// 最终兜底：复制链接
  static Future<void> toFacebook({required String url}) async {
    if (kDebugMode) {
      print('📱 [ShareUtils] Attempting Facebook share');
    }

    final encodedUrl = Uri.encodeComponent(url);

    // ① 用 App 打开网页分享路由
    final fbApp = Uri.parse(
        'fb://facewebmodal/f?href=https://www.facebook.com/sharer/sharer.php?u=$encodedUrl');
    if (await _tryLaunch(fbApp)) return;

    // ② 退到网页分享（兼容未安装）
    final web = Uri.parse(
        'https://www.facebook.com/sharer/sharer.php?u=$encodedUrl');
    if (await _tryLaunch(web)) return;

    // ③ 兜底：复制链接
    if (kDebugMode) {
      print('📋 [ShareUtils] Facebook not available, copying to clipboard');
    }
    await Clipboard.setData(ClipboardData(text: url));
  }
}