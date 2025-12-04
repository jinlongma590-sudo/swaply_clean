// lib/services/app_update_service.dart
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 服务器返回的更新信息
class AppUpdateInfo {
  final String latestVersion;  // 展示用
  final int latestBuild;       // 最新 buildNumber
  final int minSupportedBuild; // 最低可用（小于它时强制）
  final String? androidApkUrl;
  final String? iosStoreUrl;
  final String? changelog;
  final bool forceUpdate;

  AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.minSupportedBuild,
    required this.androidApkUrl,
    required this.iosStoreUrl,
    required this.changelog,
    required this.forceUpdate,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

    return AppUpdateInfo(
      latestVersion: (json['latest_version'] ?? '').toString(),
      latestBuild: toInt(json['latest_build']),
      minSupportedBuild: toInt(json['min_supported_build']),
      androidApkUrl: json['android_apk_url']?.toString(),
      iosStoreUrl: json['ios_store_url']?.toString(),
      changelog: json['changelog']?.toString(),
      forceUpdate: json['force_update'] == true,
    );
  }
}

class AppUpdateService {
  // 你刚才上线的地址
  static const String _configUrl =
      'https://swaply.cc/app/app-update.json';

  // 防重复（一次冷启动只弹一次）
  static bool _checkedThisLaunch = false;

  /// 在页面渲染后调用；发现新版本时弹窗提示（默认非强制）
  static Future<void> checkForUpdates(
      BuildContext context, {
        bool showNoUpdateToast = false,
      }) async {
    if (_checkedThisLaunch) return;
    _checkedThisLaunch = true;

    try {
      // 当前 App 版本（buildNumber 对应 pubspec 的 +N）
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      // 读取配置
      final resp =
      await http.get(Uri.parse(_configUrl)).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final cfg = AppUpdateInfo.fromJson(data);

      // 判断是否需要提醒
      if (currentBuild < cfg.minSupportedBuild) {
        _showDialog(context, cfg, force: true);
      } else if (currentBuild < cfg.latestBuild) {
        _showDialog(context, cfg, force: cfg.forceUpdate);
      } else {
        if (showNoUpdateToast && context.mounted) {
          // 需要的话可以给个轻提示：已是最新
          // ScaffoldMessenger.of(context).showSnackBar(
          //   const SnackBar(content: Text('当前已是最新版本')),
          // );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        // debug 打印即可，不要影响主流程
        // ignore: avoid_print
        print('AppUpdateService error: $e');
      }
    }
  }

  static void _showDialog(
      BuildContext context,
      AppUpdateInfo info, {
        required bool force,
      }) {
    final String body = [
      if (info.latestVersion.isNotEmpty) '发现新版本：${info.latestVersion}',
      if ((info.changelog ?? '').trim().isNotEmpty) '',
      if ((info.changelog ?? '').trim().isNotEmpty) info.changelog!.trim(),
    ].join('\n');

    // ✅ 改为“非阻塞排队”：让出当前帧，稍作延时，避免与首帧路由/欢迎弹窗/深链竞争
    if (!context.mounted) return;
    Future.microtask(() async {
      if (!context.mounted) return;
      await Future.delayed(const Duration(milliseconds: 180)); // 120–200ms 皆可
      if (!context.mounted) return;

      // 保持原有 UI 与行为不变（不 await；不影响调用方继续执行）
      // ignore: use_build_context_synchronously
      showDialog(
        context: context,
        barrierDismissible: !force,
        builder: (ctx) {
          return WillPopScope(
            onWillPop: () async => !force,
            child: AlertDialog(
              title: Text(force ? '必须更新才能继续使用' : '发现新版本'),
              content: Text(
                body.isEmpty
                    ? 'Swaply 有新版本，可以前往下载最新安装包。'
                    : body,
              ),
              actions: [
                if (!force)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('以后再说'),
                  ),
                TextButton(
                  onPressed: () async {
                    final String? url = Platform.isAndroid
                        ? info.androidApkUrl
                        : info.iosStoreUrl;

                    if (url != null && url.isNotEmpty) {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    }

                    if (!force && ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                  },
                  child: const Text('立即更新'),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
